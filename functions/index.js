const { onCall, HttpsError } = require("firebase-functions/v2/https");
const { initializeApp } = require("firebase-admin/app");
const { getAuth } = require("firebase-admin/auth");
const { getFirestore } = require("firebase-admin/firestore");

initializeApp();

const VALID_ROLES = ["manager", "technician"];

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
