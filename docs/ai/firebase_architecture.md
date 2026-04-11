# KitchenGuard — Firebase Architecture

---

# Authentication Architecture

Firebase Auth with email/password, using custom claims for role management.

## Auth Flow

```
App boot → Firebase.initializeApp()
    ↓
Auth gate (app.dart)
    ├─ Not authenticated → AuthScreen (login / register)
    ├─ Authenticated, no role claim → Role picker screen
    └─ Authenticated, has role → JobsHome
```

## Role Management

Roles are **user-level** (Firebase custom claims), not device-level.

Custom claims format: `{ "role": "manager" }` or `{ "role": "technician" }`.

`AppRoleNotifier` reads role from two sources:
1. **Primary:** Firebase ID token custom claims (`refreshFromClaims()`)
2. **Fallback:** SharedPreferences cache (offline support)

Role assignment via `setUserRole` Cloud Function (`functions/index.js`):
- New user (no existing role) can self-assign any role (bootstrap)
- Manager can assign any role to any user
- Technician with existing role cannot self-change (must ask manager)

## Key Auth Files

```
lib/services/auth_service.dart         — FirebaseAuth wrapper
lib/providers/auth_provider.dart       — authStateProvider, authServiceProvider
lib/providers/app_role_provider.dart   — AppRoleNotifier (claims + local cache)
lib/presentation/screens/auth_screen.dart — login/register UI
lib/app.dart                           — auth gate (routes by auth + role state)
functions/index.js                     — setUserRole Cloud Function
```

## Sign-Out

Sign-out button in JobsHome AppBar. Clears local role cache and signs out of Firebase Auth.

---

# Firestore Schema

Firestore stores scheduling data for cross-device access. Media files remain on the local filesystem (synced via Firebase Storage).

```
jobs/{jobId}                      — full job metadata (mirrors job.json)
dayNotes/{date}                   — { notes: [...DayNote objects] }
daySchedules/{date}               — { shopMeetupTime, firstRestaurantName, firstArrivalTime }
users/{userId}                    — reserved (email, displayName, role, createdAt)
clients/{clientId}                — reserved (empty, denied by rules)
```

## Hybrid Repository Pattern

Repository providers switch implementation based on auth state:

- **Authenticated**: `CloudJobRepository` wraps local repo and mirrors writes to Firestore. `CloudDayNoteRepository` / `CloudDayScheduleRepository` use Firestore directly (with built-in offline cache).
- **Not authenticated**: All repos use local filesystem implementations (pre-Step 3 behavior).

This is transparent to `JobsService` and all upstream callers — the repository interface is unchanged.

## Cloud Read/Write Flow

- **Jobs**: reads always from local (fast, offline-first); writes go to local first, then Firestore (fire-and-forget with Firestore offline queueing). Cloud-to-local pull via `CloudJobRepository.fetchCloudJobs()` on app-open / pull-to-refresh.
- **DayNotes / DaySchedules**: when authenticated, reads and writes go directly to Firestore (offline cache handles offline reads, writes queue automatically).

## Key Firestore Files

```
firestore.rules                                             — security rules
lib/data/repositories/cloud_job_repository.dart             — hybrid local+Firestore JobRepository
lib/data/repositories/cloud_day_note_repository.dart        — Firestore DayNoteRepository
lib/data/repositories/cloud_day_schedule_repository.dart    — Firestore DayScheduleRepository
lib/providers/repository_providers.dart                     — auth-based provider switching
```

## Security Rules Summary

- Any authenticated user can read/write jobs
- Only managers can write dayNotes and daySchedules
- Any authenticated user can read dayNotes and daySchedules
- `clients` collection is denied (reserved for future)

---

# Firebase Storage Architecture

Firebase Storage stores uploaded photos and videos. The local filesystem remains the source of truth; Storage is a cloud mirror for cross-device access and web viewing.

## Storage Path Convention

Upload paths mirror the local folder structure:

```
jobs/{jobId}/{relativePath}
```

Examples:

```
jobs/abc-123/Hoods/hood_1__unit-xyz/Before/photo_20260323_091500.jpg
jobs/abc-123/Videos/Exit/Exit_video_20260323_120000.mp4
jobs/abc-123/PreCleanLayout/photo_20260323_083000.jpg
```

## Sync Status Fields

`PhotoRecord` and `VideoRecord` each have three nullable cloud sync fields (backward-compatible — omitted from JSON when null):

```
syncStatus    String?   'pending' | 'uploading' | 'synced' | 'error' (null = pending)
cloudUrl      String?   Firebase Storage download URL (set after successful upload)
uploadedBy    String?   UID of the user who uploaded the file
```

Computed helpers on both models: `isSynced`, `needsUpload`.

## Upload Flow

```
Media captured → saved to local filesystem → PhotoRecord/VideoRecord created (syncStatus 'pending')
    ↓
UploadController.uploadPhoto(jobDir, jobId, photoId)
    ↓
Mark syncStatus = 'uploading' → save job
    ↓
StorageService.uploadPhoto → Firebase Storage PUT
    ↓
On success: syncStatus = 'synced', cloudUrl = downloadUrl, uploadedBy = uid → save job
On failure: syncStatus = 'error' → save job (retry later via upload queue)
```

## Upload Queue

A persistent queue tracks which media files need uploading. Stored as `upload_queue.json` at the jobs root (`KitchenCleaningJobs/`). Survives app restarts.

```
Media captured → PhotoRecord/VideoRecord created → saveJob
    ↓
UploadQueue.enqueue (jobId, jobDirPath, mediaId, mediaType)
    ↓
Queue persisted to upload_queue.json
    ↓
UploadQueue.processNext(controller) — dequeue + UploadController.uploadPhoto/Video
    ↓
On success: entry marked 'completed'
On failure: entry marked 'failed', retryCount incremented (max 10)
```

Queue entries track: `id`, `jobId`, `jobDirPath`, `mediaId`, `mediaType`, `status` (pending/uploading/completed/failed), `retryCount`, `createdAt`, `lastAttempt`.

Auto-enqueue hooks in `JobsService`:
- `addPhotoRecord` (unit before/after photos)
- `persistAndRecordPreCleanLayoutPhoto`
- `persistAndRecordVideo`

On load, stale 'uploading' entries (app killed mid-upload) are reset to 'pending'. Duplicate detection prevents re-enqueuing the same media. `onNewEntry` callback triggers immediate upload attempt after capture.

## Background Upload

Uploads are processed automatically via three triggers:
1. **Immediate** — `UploadQueue.onNewEntry` callback fires after each capture, triggering `UploadProgressNotifier` to process the queue
2. **Periodic background** — workmanager task runs every ~15 minutes with network constraint
3. **Manual** — user taps the sync indicator in Jobs Home AppBar

Processing checks connectivity before each item and applies exponential backoff for failed retries (1 min, 2 min, 4 min, ... capped at 30 min). Max 10 retries per entry.

The workmanager callback runs in a separate isolate and rebuilds its own Firebase/repository/service stack since Riverpod state isn't shared across isolates.

## Download and Caching

When a photo or video's local file is missing but it has a `cloudUrl`, the app falls back to loading from Firebase Storage.

**Photos** — all gallery and viewer screens use `CloudAwareImage`, a local-first widget:
1. Local file exists on disk → `Image.file` (unchanged, zero latency)
2. Local file missing, `cloudUrl` set → `CachedNetworkImage` (disk-cached by URL)
3. Neither available → missing-file placeholder

Cloud-loaded thumbnails display a small cloud badge so the user can distinguish local vs. cloud-only photos.

**Videos** — `VideoPlayerScreen` accepts either a local `File` or a `networkUrl`:
1. Local file found → `VideoPlayerController.file` (unchanged)
2. Local missing, `cloudUrl` set → `VideoPlayerController.networkUrl` (streaming)
3. Neither → "Video file missing" snackbar

## Key Storage Files

```
storage.rules                                    — Firebase Storage security rules
lib/services/storage_service.dart                — Firebase Storage wrapper (upload, delete, getUrl)
lib/services/upload_controller.dart              — coordinates single-file upload + sync status updates
lib/services/upload_queue.dart                   — persistent upload queue + processor
lib/services/background_upload_service.dart      — backoff logic, connectivity checks, workmanager callback
lib/domain/models/upload_queue_entry.dart        — queue entry model
lib/providers/service_providers.dart             — storageServiceProvider, uploadControllerProvider, uploadQueueProvider
lib/providers/upload_progress_provider.dart      — UploadProgressNotifier + uploadProgressProvider (UI state)
lib/domain/models/photo_record.dart              — syncStatus, cloudUrl, uploadedBy fields
lib/domain/models/video_record.dart              — syncStatus, cloudUrl, uploadedBy fields
lib/domain/merge/job_merger.dart                 — pure-function merge logic for local + cloud jobs
lib/presentation/widgets/cloud_aware_image.dart  — local-first image with cloud fallback + badge
```

## Storage Security Rules

- Any authenticated user can read from `jobs/{jobId}/...`
- Any authenticated user can write to `jobs/{jobId}/...` (photos: 10MB limit, videos: 500MB limit)
- Everything else is denied

---

# Sync Engine

The sync engine coordinates bidirectional data flow between devices.

## Data Flow Directions

```
Scheduling data (jobs, day notes, day schedules):
  Cloud (Firestore) → Device (local filesystem)
  Real-time via Firestore .snapshots() listener; manual via pull-to-refresh.

Documentation data (photos, videos, field notes):
  Device (local filesystem) → Cloud (Firebase Storage + Firestore)
  Technicians capture locally; uploads sync when connectivity allows.
```

## Sync Triggers

| Trigger | Mechanism |
|---------|-----------|
| Real-time | Firestore `.snapshots()` stream on `jobs` collection, debounced 1 s |
| Manual | Pull-to-refresh or tap sync indicator → `pullNow()` (one-time fetch + merge) |
| Connectivity | `Connectivity.onConnectivityChanged` updates offline banner |

## Cloud-Only Job Provisioning

When `mergeCloudJobs()` encounters a Firestore job with no local folder:
1. Creates folder at `{root}/{sanitized_name}_{jobId_prefix}`
2. Saves `job.json` via local repository (no re-push)
3. Media files are cloud-only — viewable via `CloudAwareImage`

## Combined Sync State

`SyncState` merges pull and upload status:
- `isOnline` — connectivity stream from `connectivity_plus`
- `isPulling` — Firestore merge in progress (from stream or manual pull)
- `isListening` — Firestore real-time listener is active
- `isUploading` — upload queue processing
- `uploadPending` — count of queued media uploads
- `lastPullTime` — timestamp of last successful merge
- `isSynced` — all clear (listening, no pull, no upload, no pending)

## Sync UI

- **AppBar indicator**: cloud-done (synced) / spinner (active) / badge (pending) / cloud-off (offline)
- **Offline banner**: `MaterialBanner` below AppBar when device is offline
- **Manual sync**: tap indicator to trigger pull + upload

## Broken-URL Recovery

When `CloudAwareImage` fails to load a `cloudUrl`, the `onCloudUrlBroken` callback fires (at most once per URL). The gallery screen passes the `photoId` to `JobsService.requeueBrokenPhoto()`, which resets `syncStatus` and `cloudUrl` to null and re-enqueues the photo for upload — but only if the local file exists on disk.

## Multi-Device Merge

When multiple devices document the same job, their `job.json` files may diverge.
`JobMerger.merge(local:, cloud:)` reconciles these into a single `Job`:

**Scheduling fields** (restaurantName, scheduledDate, sortOrder, completedAt, address, city, accessType, etc.) — **last-write-wins** via `updatedAt` timestamp.

**Documentation data** (photos, videos, notes) — **append-only union by ID**:
- `photoId` / `videoId` / `noteId` are UUID v4, collision-safe across devices.
- If the same ID exists in both versions:
  - Sync metadata: prefer the better `syncStatus` (synced > uploading > pending > error > null).
  - Soft-deletion is additive: if either side is deleted, the merge result is deleted.
  - Local filesystem fields (`relativePath`, `fileName`, `subPhase`, etc.) always come from local.
- Records only on one side are appended (local order first, then cloud-only items).

**Units** matched by `unitId`; photos within matched units are merged with the same append-only logic. Cloud-only units are appended. Local-only units are kept.

**Notes** use last-write-wins on `updatedAt` for text content when the same `noteId` exists on both sides. Deletion takes priority over text edits.

**Pull flow**: `CloudJobRepository.mergeCloudJobs()` takes a list of cloud job documents, matches them to local jobs by `jobId`, merges, and saves to the local filesystem only (no re-push to Firestore). Cloud-only jobs are provisioned locally. After merge, if the merged result has MORE documentation records than the cloud version, the result is pushed back to Firestore to recover from stale overwrites.

## Key Sync Files

```
lib/providers/sync_provider.dart                   — SyncNotifier (stream sub + debounce) + SyncState
lib/providers/upload_progress_provider.dart         — upload queue progress (merged into SyncState)
lib/data/repositories/cloud_job_repository.dart     — watchCloudJobs + mergeCloudJobs + pullFromCloud
lib/domain/merge/job_merger.dart                    — merge logic (scheduling LWW + docs append-only)
lib/services/background_upload_service.dart         — workmanager background upload processing
lib/presentation/widgets/cloud_aware_image.dart     — local-first image + onCloudUrlBroken recovery
lib/application/jobs_service.dart                   — requeueBrokenPhoto (sync field reset + re-enqueue)
```
