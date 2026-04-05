const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");
const { getStorage } = require("firebase-admin/storage");
const crypto = require("crypto");
const fs = require("fs/promises");
const os = require("os");
const path = require("path");
const { spawn } = require("child_process");
const ffmpegPath = require("ffmpeg-static");
const ffprobePath = require("ffprobe-static").path;

initializeApp();

const VALID_ROLES = ["manager", "technician"];
const DEFAULT_TARGET_MB = 10;
const ONE_MB_BYTES = 1024 * 1024;
const SIGNED_URL_TTL_MS = 15 * 60 * 1000;

/**
 * Callable Cloud Function to set a user's role via custom claims.
 *
 * Allowed callers:
 *   - A user with no existing role can self-assign (bootstrap).
 *   - A manager can assign any role to any user.
 *
 * Payload: { uid: string, role: "manager" | "technician" }
 */
exports.setUserRole = onCall(async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Must be authenticated.");
  }

  const { uid, role } = request.data;

  if (!uid || typeof uid !== "string") {
    throw new HttpsError("invalid-argument", "uid is required.");
  }
  if (!VALID_ROLES.includes(role)) {
    throw new HttpsError(
      "invalid-argument",
      `Invalid role. Must be one of: ${VALID_ROLES.join(", ")}`
    );
  }

  const callerUid = request.auth.uid;
  const callerRole = request.auth.token.role;

  // Self-assignment: allowed only if the caller has no existing role (bootstrap).
  // Otherwise only managers can assign roles.
  if (callerUid !== uid) {
    if (callerRole !== "manager") {
      throw new HttpsError(
        "permission-denied",
        "Only managers can assign roles to other users."
      );
    }
  } else if (callerRole && callerRole !== "manager") {
    throw new HttpsError(
      "permission-denied",
      "Role already assigned. Ask a manager to change it."
    );
  }

  await getAuth().setCustomUserClaims(uid, { role });

  // Mirror role to Firestore users collection for web dashboard visibility.
  try {
    const userRecord = await getAuth().getUser(uid);
    await getFirestore().collection("users").doc(uid).set(
      {
        email: userRecord.email || null,
        displayName: userRecord.displayName || userRecord.email?.split("@")[0] || null,
        role,
        roleUpdatedAt: new Date().toISOString(),
      },
      { merge: true }
    );
  } catch (e) {
    // Non-critical — user doc update is best-effort.
    console.warn("Failed to update user doc in Firestore:", e.message);
  }

  return { success: true, uid, role };
});

/**
 * Callable Cloud Function to prepare a best-effort compressed video download.
 *
 * Payload:
 * {
 *   jobId: string,
 *   videoId: string?,
 *   relativePath: string, // e.g. Videos/Exit/file.mp4
 *   fileName: string?,
 *   targetMb: number?      // default 10
 * }
 *
 * Returns:
 * {
 *   downloadUrl: string,
 *   fileName: string,
 *   sourceBytes: number,
 *   outputBytes: number,
 *   targetBytes: number,
 *   wasCompressed: boolean,
 *   note: string
 * }
 */
exports.prepareCompressedVideoDownload = onCall(
  { timeoutSeconds: 540, memory: "1GiB" },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Must be authenticated.");
    }

    const jobId = _asNonEmptyString(request.data?.jobId);
    const relativePath = _sanitizeRelativePath(request.data?.relativePath);
    const videoId = _asOptionalString(request.data?.videoId);
    const fileName = _asOptionalString(request.data?.fileName);
    const requestedTargetMb = Number(request.data?.targetMb);
    const targetMb =
      Number.isFinite(requestedTargetMb) && requestedTargetMb > 0
        ? requestedTargetMb
        : DEFAULT_TARGET_MB;
    const targetBytes = Math.round(targetMb * ONE_MB_BYTES);

    if (!jobId) {
      throw new HttpsError("invalid-argument", "jobId is required.");
    }
    if (!relativePath) {
      throw new HttpsError("invalid-argument", "relativePath is required.");
    }
    if (!relativePath.startsWith("Videos/")) {
      throw new HttpsError(
        "invalid-argument",
        "relativePath must be under Videos/."
      );
    }

    const bucket = getStorage().bucket();
    const sourcePath = `jobs/${jobId}/${relativePath}`;
    const sourceFile = bucket.file(sourcePath);

    const [exists] = await sourceFile.exists();
    if (!exists) {
      throw new HttpsError("not-found", "Source video does not exist in Storage.");
    }

    const [sourceMetadata] = await sourceFile.getMetadata();
    const sourceBytes = Number(sourceMetadata.size || 0);
    const originalName = fileName || path.posix.basename(relativePath);
    const fallbackUrl = await _createSignedReadUrl(sourceFile);

    // If already under target, avoid unnecessary quality loss.
    if (sourceBytes > 0 && sourceBytes <= targetBytes) {
      return {
        downloadUrl: fallbackUrl,
        fileName: originalName,
        sourceBytes,
        outputBytes: sourceBytes,
        targetBytes,
        wasCompressed: false,
        note: `Already under ${targetMb} MB; downloading original.`,
      };
    }

    let tempDir = "";
    try {
      tempDir = await fs.mkdtemp(path.join(os.tmpdir(), "kg-video-"));
      const sourceExt = path.extname(relativePath) || ".mp4";
      const inputPath = path.join(tempDir, `input${sourceExt}`);
      const outputPathLocal = path.join(tempDir, "output.mp4");

      await sourceFile.download({ destination: inputPath });
      const durationSeconds = await _probeDurationSeconds(inputPath);
      if (!Number.isFinite(durationSeconds) || durationSeconds <= 0) {
        throw new Error("Unable to determine source video duration.");
      }

      const multipliers = [1.0, 0.75, 0.55, 0.4];
      let bestBytes = Number.POSITIVE_INFINITY;
      let bestKbps = 0;

      for (const multiplier of multipliers) {
        const videoKbps = _targetVideoKbps({
          durationSeconds,
          targetBytes,
          audioKbps: 96,
          multiplier,
        });
        if (videoKbps <= 0) continue;

        await _runFfmpeg({
          inputPath,
          outputPath: outputPathLocal,
          videoKbps,
          audioKbps: 96,
        });

        const stat = await fs.stat(outputPathLocal);
        if (stat.size < bestBytes) {
          bestBytes = stat.size;
          bestKbps = videoKbps;
        }
        if (stat.size <= targetBytes) {
          break;
        }
      }

      if (!Number.isFinite(bestBytes) || bestBytes <= 0) {
        return {
          downloadUrl: fallbackUrl,
          fileName: originalName,
          sourceBytes,
          outputBytes: sourceBytes,
          targetBytes,
          wasCompressed: false,
          note: "Compression unavailable; downloaded original video.",
        };
      }

      const outputStoragePath = _compressedStoragePath({
        jobId,
        relativePath,
        videoId,
        targetMb,
      });
      const outputFile = bucket.file(outputStoragePath);
      await outputFile.save(await fs.readFile(outputPathLocal), {
        metadata: {
          contentType: "video/mp4",
          cacheControl: "private, max-age=3600",
          metadata: {
            sourcePath,
            targetMb: String(targetMb),
            sourceBytes: String(sourceBytes),
            transcodeVideoKbps: String(bestKbps),
            generatedAt: new Date().toISOString(),
          },
        },
      });

      const compressedUrl = await _createSignedReadUrl(outputFile);
      const compressedName = _compressedFileName(originalName, targetMb);
      const note =
        bestBytes <= targetBytes
          ? `Compressed for email target (~${targetMb} MB).`
          : `Best effort complete (${_bytesToMb(bestBytes)} MB; target ${targetMb} MB).`;

      return {
        downloadUrl: compressedUrl,
        fileName: compressedName,
        sourceBytes,
        outputBytes: bestBytes,
        targetBytes,
        wasCompressed: bestBytes < sourceBytes,
        note,
      };
    } catch (e) {
      console.error("prepareCompressedVideoDownload failed:", e);
      return {
        downloadUrl: fallbackUrl,
        fileName: originalName,
        sourceBytes,
        outputBytes: sourceBytes,
        targetBytes,
        wasCompressed: false,
        note: "Compression failed; downloaded original video.",
      };
    } finally {
      if (tempDir) {
        await fs.rm(tempDir, { recursive: true, force: true });
      }
    }
  }
);

function _asNonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function _asOptionalString(value) {
  return typeof value === "string" && value.trim().length > 0
    ? value.trim()
    : null;
}

function _sanitizeRelativePath(value) {
  if (typeof value !== "string") return null;
  const normalized = value.replaceAll("\\", "/").replace(/^\/+/, "");
  if (normalized.includes("..")) return null;
  if (normalized.length === 0) return null;
  return normalized;
}

function _compressedFileName(originalName, targetMb) {
  const ext = path.posix.extname(originalName) || ".mp4";
  const base = path.posix.basename(originalName, ext);
  return `${base}_${targetMb}mb.mp4`;
}

function _compressedStoragePath({ jobId, relativePath, videoId, targetMb }) {
  const sourceToken =
    videoId ||
    crypto.createHash("sha1").update(`${jobId}:${relativePath}`).digest("hex").slice(0, 12);
  const safeToken = sourceToken.replaceAll(/[^a-zA-Z0-9_-]/g, "_");
  return `jobs/${jobId}/Videos/Compressed/${safeToken}_${targetMb}mb.mp4`;
}

function _bytesToMb(bytes) {
  return (bytes / ONE_MB_BYTES).toFixed(1);
}

async function _createSignedReadUrl(file) {
  const [url] = await file.getSignedUrl({
    version: "v4",
    action: "read",
    expires: Date.now() + SIGNED_URL_TTL_MS,
  });
  return url;
}

async function _probeDurationSeconds(inputPath) {
  const args = [
    "-v",
    "error",
    "-show_entries",
    "format=duration",
    "-of",
    "default=noprint_wrappers=1:nokey=1",
    inputPath,
  ];
  const result = await _runCommand(ffprobePath, args);
  const seconds = Number.parseFloat(result.stdout.trim());
  return Number.isFinite(seconds) ? seconds : NaN;
}

function _targetVideoKbps({ durationSeconds, targetBytes, audioKbps, multiplier }) {
  const totalKbps = (targetBytes * 8) / durationSeconds / 1000;
  const adjustedTotal = totalKbps * multiplier;
  // Reserve room for container overhead and audio stream.
  const videoKbps = Math.floor(adjustedTotal * 0.92 - audioKbps);
  return Math.max(120, videoKbps);
}

async function _runFfmpeg({ inputPath, outputPath, videoKbps, audioKbps }) {
  const maxRate = Math.round(videoKbps * 1.25);
  const bufSize = Math.round(videoKbps * 2);
  const args = [
    "-y",
    "-i",
    inputPath,
    "-c:v",
    "libx264",
    "-preset",
    "veryfast",
    "-b:v",
    `${videoKbps}k`,
    "-maxrate",
    `${maxRate}k`,
    "-bufsize",
    `${bufSize}k`,
    "-c:a",
    "aac",
    "-b:a",
    `${audioKbps}k`,
    "-movflags",
    "+faststart",
    outputPath,
  ];
  await _runCommand(ffmpegPath, args);
}

function _runCommand(bin, args) {
  return new Promise((resolve, reject) => {
    const child = spawn(bin, args);
    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString();
    });
    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString();
    });
    child.on("error", (err) => reject(err));
    child.on("close", (code) => {
      if (code === 0) {
        resolve({ stdout, stderr });
      } else {
        reject(new Error(`Command failed (${bin}) with code ${code}: ${stderr}`));
      }
    });
  });
}
