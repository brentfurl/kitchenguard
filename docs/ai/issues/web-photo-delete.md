# Issue: Web console photo soft-delete

## Task
Add the ability to remove (soft-delete) photos from the web management console's enlarged photo view. Deleted photos should disappear from the phone app as well via the existing Firestore sync + merger flow.

## Risk Level
High — touches deletion behavior and writes to the shared `units` array in Firestore.

## Branch
`feature/web-photo-delete`

## Changes Made

- `lib/web/web_job_repository.dart` — Added `softDeletePhoto()` method. Re-reads the job from Firestore, finds the target photo by unitId/phase/photoId, sets `status: 'deleted'` and `deletedAt`, writes back updated `units` array via `updateFields`.

- `lib/web/screens/web_job_detail_screen.dart` — Threaded `jobId`, `unitId`, `phase`, and `WebJobRepository` from `_JobDetailBody` through `_UnitSection` → `_PhotoGrid` → `_PhotoThumbnail`. Added a trash icon button (top-left) to the enlarged photo dialog. Added `_confirmDelete()` with a confirmation `AlertDialog` before performing the soft delete. Shows success/error snackbar.

## Open Questions / Risks

1. **Race with phone `set()` writes**: If the phone does a full `set()` on the job doc between the web's delete and the phone's next merge cycle, the deletion could be temporarily overwritten. The merger's additive-delete logic should correct this on the next sync. Acceptable for V1.

2. **`units` array scope**: Writing the full `units` array (rather than a single photo field) means concurrent web edits could conflict. The re-read-before-write minimises the window; consistent with existing notes pattern.

3. **No undo**: Soft delete is reversible at the database level but no undo UI exists. Confirmation dialog is the safety net.

4. **Firebase Storage blob not deleted**: Matches existing mobile behaviour — blob stays in Storage, clients use `isActive` filtering.

## Review Status
- [x] Builder complete
- [x] Reviewer pass (same-session)
- [x] Safety pass (same-session)
- [ ] Test pass
- [ ] Human approval
