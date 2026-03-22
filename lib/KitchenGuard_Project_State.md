# KitchenGuard — Project State Snapshot (Field-Ready v1)

## 1. Project Overview

**App Name:** KitchenGuard  
**Platform:** Flutter (Android primary, iOS planned)

**Primary Use:**  
Field technicians capturing cleaning documentation for restaurant hood systems.

**Core data captured:**

- Jobs (restaurant + shift date)
- Units (hoods, fans, misc)
- Before / After photos
- Exit videos
- Other videos
- Job notes
- Pre-clean layout photos

**Primary goal right now:**  
Reliable **field-ready offline documentation tool** for technicians.

The app prioritizes:

- offline-first storage
- reliability in field conditions
- simple workflows for technicians

---

# 2. Architecture

The app uses a layered architecture with Riverpod state management.

```
UI (screens — ConsumerStatefulWidget)
    ↓
Riverpod Providers (state management)
    - jobListProvider      (AsyncNotifier — all scanned jobs)
    - dayNotesProvider     (AsyncNotifier — all active day notes)
    - jobDetailProvider    (family AsyncNotifier — single job by path)
    - jobsServiceProvider  (Provider — JobsService instance)
    - repository providers (Provider — repository + storage instances)
    ↓
Controller (job_detail_controller.dart — mutation delegator)
    ↓
Service Layer (jobs_service.dart)
    ↓
Repository Layer (abstractions for Phase 4 cloud swap)
    - JobRepository (abstract) → LocalJobRepository
    - DayNoteRepository (abstract) → LocalDayNoteRepository
    ↓
Storage Layer
    - job_store.dart
    - image_file_store.dart
    - video_file_store.dart
    - job_scanner.dart
    - day_note_store.dart
```

### Responsibilities

#### UI (Riverpod consumers)

- Display jobs (watch providers for loading/error/data states)
- Capture photos/videos
- Add notes
- Export job
- Navigate between screens
- Invalidate providers after mutations to trigger reload

#### Providers

- Manage async state (loading, error, data) via AsyncNotifier
- Centralize data loading and caching
- Replace manual setState + _loadAll patterns

#### Controller

- Delegate mutations to JobsService
- Provide computed counts
- Resolve file paths

#### Services

Business logic:

- Persist metadata
- Soft deletes
- Export generation

#### Repository

Abstract data access:

- JobRepository: scan, load, save, delete jobs; persist media
- DayNoteRepository: load, save day notes
- Local implementations wrap existing storage classes
- Phase 4 adds cloud-aware implementations behind the same interface

#### Storage

Handles filesystem interaction:

- File writes
- Job JSON read/write
- Startup integrity scanning

---

# 3. Storage Model

All jobs stored locally on device.

```
/data/data/<package>/app_flutter/KitchenCleaningJobs/
```

Example job structure:

```
KitchenCleaningJobs/
  day_notes.json        ← date-level shift notes (all dates)
  Json_test_2026_03_06/
      job.json

      PreCleanLayout/

      Hoods/
          hood_1__unit-177.../
              Before/
              After/

      Fans/
      Misc/

      Videos/
          Exit/
          Other/
```

Key points:

- Jobs are **self-contained folders**
- Media files live inside the job folder
- `job.json` tracks metadata only
- `day_notes.json` lives in the root `KitchenCleaningJobs/` directory, not inside any job folder

---

# 4. job.json Schema

Example structure (schema version 3):

```json
{
  "jobId": "a1b2c3d4-...",
  "restaurantName": "Json test",
  "shiftStartDate": "2026-03-06",
  "scheduledDate": "2026-03-20",
  "sortOrder": 0,
  "createdAt": "2026-03-06T14:00:00.000Z",
  "updatedAt": "2026-03-06T15:30:00.000Z",
  "schemaVersion": 3,
  "units": [
    {
      "unitId": "e5f6a7b8-...",
      "type": "hood",
      "name": "hood 1",
      "unitFolderName": "hood_1__unit-e5f6a7b8...",
      "isComplete": false,
      "photosBefore": [
        {
          "photoId": "c9d0e1f2-...",
          "fileName": "hood_1_before_20260306_140500.jpg",
          "relativePath": "Hoods/hood_1__unit-e5f6.../Before/hood_1_before_20260306_140500.jpg",
          "capturedAt": "2026-03-06T14:05:00.000Z",
          "status": "local"
        }
      ],
      "photosAfter": []
    }
  ],
  "preCleanLayoutPhotos": [],
  "notes": [],
  "videos": {
    "exit": [],
    "other": []
  }
}
```

Key changes from schema version 1:

- `jobId` and `unitId` are now UUID v4 (previously microsecond-based)
- `photoId` added to all photo records (UUID v4)
- `videoId` added to all video records (UUID v4)
- `updatedAt` bumped on every `job.json` write
- `schemaVersion` integer field added (missing = version 1)
- `scheduledDate` (String?, YYYY-MM-DD) — nullable, omitted from JSON when null
- `sortOrder` (int?, 0-based within a day) — nullable, omitted from JSON when null

Schema version 3 additions (Phase 3):

- `completedAt` (String?, ISO 8601 UTC) on Job — nullable, omitted when null
- `subPhase` (String?) on photo records — 'filters-on'/'filters-off' (hood), 'closed'/'open' (fan), null (misc)

---

# 5. Pre-clean Layout Feature

Purpose: capture reference photos **before equipment is moved for cleaning**.

Characteristics:

- Job-level gallery
- Before-only photos
- Can be captured anytime during the job
- Stored in:

```
PreCleanLayout/
```

Tracked in metadata:

```
preCleanLayoutPhotos[]
```

---

# 6. Important Design Rules

### File resolution rule

All media must resolve using:

```
File(p.join(jobDir.path, relativePath))
```

`relativePath` is authoritative.

---

### Unit folder naming

```
<unitNameSanitized>__<unitId>
```

Example:

```
hood_1__unit-177...
```

---

### Soft delete rule

Deleted media:

```
status = "deleted"
```

Files remain on disk but are hidden from the UI.

---

### Missing media rule

Media is considered missing only if:

```
!File(jobDir + relativePath).exists()
```

---

# 7. Export System

Export creates a zip file:

```
KitchenGuard_<Restaurant>_<Timestamp>.zip
```

Export location:

```
cache/KitchenGuardExports/
```

Zip contains:

```
job.json
Hoods/
Fans/
Misc/
Videos/
notes.txt (optional)
```

Pre-clean layout photos are **not exported**.

---

# 8. Notes Export

A `notes.txt` file is generated when **field notes** (tech-entered `notes[]`) exist. Manager job notes (`managerNotes[]`) are NOT included in the export.

Example:

```
Notes
Restaurant: Test_Restaurant
Shift: 2026-03-06

- needs grease pillow
- didn't relight pilot lights
```

---

# 9. Photo UI Behavior

Photo grids:

- show only active photos
- hide deleted
- hide missing_local

Counts reflect **visible photos only**.

---

# 10. Camera Configuration

Using `image_picker`.

Rear camera forced:

```
preferredCameraDevice: CameraDevice.rear
```

# 10.1

# 10.1 Rapid Capture System

The app now supports **rapid capture photography** for high-speed field documentation.

This replaced the earlier `image_picker` confirmation workflow for unit photos.

## Purpose

Technicians often take **many photos quickly** during hood cleaning jobs.

The previous flow required:

1. Open camera
2. Take photo
3. Confirm photo
4. Return to app

This slowed documentation.

Rapid capture introduces a **persistent camera mode**.

## Rapid Capture Behavior

When entering rapid capture:

- Camera opens once
- Camera remains active between photos
- Each tap captures and saves immediately
- Subtle "Saved" feedback appears
- User can continue capturing without leaving the screen

Flow:


tap capture
↓
photo saved
↓
camera remains open
↓
tap again


This significantly reduces capture friction.

---

## Camera Configuration

Rapid capture uses the `camera` package.

Configuration:


ResolutionPreset.medium
ImageFormatGroup.jpeg
rear camera
audio disabled


Reasons:

- faster capture speed
- smaller files
- reduced storage pressure
- adequate documentation quality

---

## Rapid Capture UX Enhancements

To improve usability in field conditions:

### Portrait Orientation Lock

Rapid capture screens lock orientation to:


DeviceOrientation.portraitUp


This prevents UI rotation while technicians move around equipment.

Orientation returns to normal when leaving the screen.

---

### Capture Flash Overlay

A brief white overlay flashes after capture.

Purpose:

- mimics native camera shutter behavior
- improves perceived responsiveness
- reassures technician that the photo was captured

Duration is intentionally short (~80–100 ms).

---

### Haptic Feedback

Light haptic feedback triggers after successful capture.

Purpose:

- tactile confirmation in noisy environments
- helpful when technicians are not looking directly at the screen

---

# 10.2 Rapid Capture Scope

Rapid capture is currently used for:


Unit Before photos
Unit After photos
Pre-clean Layout photos


The behavior is consistent across all photo capture entry points.

# 10.3 Pre-clean Layout Improvements

The Pre-clean Layout feature now supports rapid capture.

Changes include:

- persistent camera capture
- visible photo count
- gallery access
- consistent behavior with unit photo capture

Purpose:

Maintain consistent camera interaction throughout the app.

---

# 10.4 Job List Improvements

The Jobs screen now includes:

### Sorting

Jobs are sorted by:


createdAt (descending)


Newest jobs appear first.

Fallback sorting may use `shiftStartDate` if needed.

---

### Job Removal

Users can remove jobs directly from the job list.

Behavior:

- confirmation dialog
- deletes the entire job folder
- removes all associated media
- updates UI immediately

This allows technicians to remove old test jobs or completed jobs.

---

# 10.5 Smart Unit Naming

When adding a new unit:

- Hood units auto-increment
- Fan units auto-increment

Examples:


hood 1
hood 2
hood 3


and


fan 1
fan 2
fan 3


Misc units are **not auto-populated**.

Users enter custom names for miscellaneous equipment.

Purpose:

- reduce typing
- maintain consistent naming
- speed up job setup
---

---

# 11. Known Limitations

### Emulator Share Bug

`share_plus` may throw:

```
PlatformException: Reply already submitted
```

Occurs only on emulator. Works correctly on physical devices.

---

# 12. Engineering Principle

Offline-first architecture.

The job folder + job.json remain the authoritative state for field documentation.

Scheduling and management data will be cloud-first when sync is implemented.

---

# 13. Typed Data Model Specifications

All domain entities have typed Dart classes in `lib/domain/models/`. Models are complete and ready for use. The service, storage, and UI layers are being migrated to use them (see Phase 1 roadmap below).

### PhotoRecord

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| photoId | String | UUID v4 | generated at creation; backfilled for old data |
| fileName | String | required | |
| relativePath | String | required | authoritative path within job folder |
| capturedAt | String | required | ISO 8601 UTC |
| status | String | 'local' | 'local' / 'deleted' / 'missing_local' |
| missingLocal | bool | false | |
| recovered | bool | false | set by JobScanner for orphan recovery |
| deletedAt | String? | null | set on soft delete |
| subPhase | String? | null | Phase 3: 'filters-on'/'filters-off' (hood), 'closed'/'open' (fan), null (misc) |

Computed: `isActive`, `isDeleted`, `isMissing`.

### VideoRecord

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| videoId | String | UUID v4 | generated at creation; backfilled for old data |
| fileName | String | required | |
| relativePath | String | required | |
| capturedAt | String | required | ISO 8601 UTC |
| status | String | 'local' | 'local' / 'deleted' |
| deletedAt | String? | null | |

### Unit

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| unitId | String | UUID v4 | |
| type | String | required | 'hood' / 'fan' / 'misc' |
| name | String | required | |
| unitFolderName | String | required | |
| isComplete | bool | false | |
| completedAt | String? | null | |
| photosBefore | List\<PhotoRecord\> | [] | |
| photosAfter | List\<PhotoRecord\> | [] | |

### Job

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| jobId | String | UUID v4 | |
| restaurantName | String | required | |
| shiftStartDate | String | required | YYYY-MM-DD |
| scheduledDate | String? | null | YYYY-MM-DD; omitted from JSON when null |
| sortOrder | int? | null | 0-based within a day; omitted from JSON when null |
| completedAt | String? | null | Phase 3: ISO 8601 UTC; null = not complete |
| createdAt | String | required | ISO 8601 UTC |
| updatedAt | String? | null | bumped on every write |
| schemaVersion | int | 3 | missing = version 1 |
| units | List\<Unit\> | [] | |
| notes | List\<JobNote\> | [] | field notes (tech-entered, included in export) |
| managerNotes | List\<ManagerJobNote\> | [] | manager job notes (NOT included in export) |
| preCleanLayoutPhotos | List\<PhotoRecord\> | [] | |
| videos | Videos | empty | |

Computed (Phase 3): `isComplete` (`completedAt != null`).

### DayNote

| Field | Type | Default | Notes |
|-------|------|---------|-------|
| noteId | String | UUID v4 | |
| date | String | required | YYYY-MM-DD |
| text | String | required | |
| createdAt | String | required | ISO 8601 UTC |
| status | String | 'active' | 'active' / 'deleted' |

Computed: `isActive`, `isDeleted`.

Stored in `KitchenCleaningJobs/day_notes.json` (root of jobs directory, not inside any job folder). Format: `{ "YYYY-MM-DD": [ {DayNote}, ... ] }`.

### Videos

| Field | Type | Default |
|-------|------|---------|
| exit | List\<VideoRecord\> | [] |
| other | List\<VideoRecord\> | [] |

### JobNote (field notes — `lib/domain/models/job_note.dart`)

| Field | Type | Default |
|-------|------|---------|
| noteId | String | UUID v4 |
| text | String | required |
| createdAt | String | required |
| status | String | 'active' |

### ManagerJobNote (manager job notes — `lib/domain/models/manager_job_note.dart`)

| Field | Type | Default |
|-------|------|---------|
| noteId | String | UUID v4 |
| text | String | required |
| createdAt | String | required |
| status | String | 'active' |

All models follow the same pattern: immutable fields, `fromJson` factory, `toJson` method, `copyWith` method. `fromJson` must handle missing fields gracefully for backward compatibility with schema version 1 data.

All model files live in `lib/domain/models/`:

```
photo_record.dart
video_record.dart
videos.dart
unit.dart
job.dart
job_note.dart
manager_job_note.dart
```

---

# 14. Collaboration Roadmap

### Phase 1: Foundation (complete)

Typed data models, UUID v4 for all entity IDs, `updatedAt` and `schemaVersion` on jobs.

**Completed:**

- `lib/domain/models/` — all model classes created (`Job`, `Unit`, `PhotoRecord`, `VideoRecord`, `Videos`, `JobNote`)
- `lib/utils/unit_sorter.dart` — canonical `UnitSorter` utility for UI, export, and upload ordering
- `AppPaths.categoryForUnitType()` — shared static helper replacing duplicate private methods
- `JobNote` moved from `lib/application/models/` to `lib/domain/models/`; all imports updated
- `lib/storage/job_store.dart` — added `readJob()` and `writeJob()` (stamps `updatedAt` to now UTC on every write; returns stamped `Job`)
- `lib/storage/job_scanner.dart` — `JobScanResult` now holds a typed `Job` field; backward-compat `jobData` getter bridges callers not yet migrated; `JobScanner` uses `Job.fromJson`, backfills missing `photoId`/`videoId` (UUID v4) with `schemaVersion` upgrade to 2, replaced private `_categoryForUnitType` with `AppPaths.categoryForUnitType()`
- `lib/application/jobs_service.dart` — fully migrated to typed models; all raw map manipulation replaced with `Job`/`Unit`/`PhotoRecord`/`VideoRecord`/`Videos` operations; `_newId()` replaced with `_uuid.v4()`; `_categoryForUnitType` replaced with `AppPaths.categoryForUnitType()`; `_getWorkflowOrderedUnits` and private sort helpers replaced with `UnitSorter.sort()`; `readJobJson`/`writeJobJson` replaced with `readJob`/`writeJob` throughout
- `lib/presentation/controllers/job_detail_controller.dart` — fully migrated to typed `Job`; `loadJob()` returns `Future<Job>`; `loadVideos()` returns `Future<List<VideoRecord>>`; `loadPreCleanLayoutPhotos()` returns `Future<List<PhotoRecord>>`; all raw map helpers removed; computed counts use typed model properties
- `lib/presentation/job_detail.dart` — fully migrated to typed `Job`/`Unit`; `_job` field replaces `_jobData`; `_getWorkflowOrderedUnits` and all duplicate sort helpers removed; replaced with `UnitSorter.sort(_job.units)`; unit card accesses typed `unit.unitId`, `unit.name`, `unit.type`, `unit.visibleBeforeCount`, `unit.visibleAfterCount`; gallery callbacks pass `List<PhotoRecord>`
- `lib/presentation/jobs_home.dart` — migrated to typed `Job` via `result.job`; `_sortJobsNewestFirst` and `_jobSortDate` use `result.job.createdAt`/`result.job.shiftStartDate`; `'Test_Restaurant'` pre-fill removed; list items use `result.job.restaurantName`, `result.job.shiftStartDate`
- `lib/presentation/screens/photo_viewer_screen.dart` — `photos` and `reloadPhotos` callback use `List<PhotoRecord>`; photo field accesses use typed model properties
- `lib/presentation/screens/unit_photo_bucket_screen.dart` — `loadPhotos` and `onOpenViewer` use `List<PhotoRecord>`; `_visiblePhotos` uses `photo.isActive`
- `lib/presentation/screens/pre_clean_layout_screen.dart` — `loadPhotos` uses `List<PhotoRecord>`
- `lib/presentation/screens/videos_screen.dart` — `loadVideos` uses `List<VideoRecord>`; video field accesses use typed model properties

**Phase 1 foundation work: COMPLETE.**

No more raw `Map<String, dynamic>` access for job/unit/photo/video data anywhere outside the storage layer.

**Automated tests added:**

- `test/domain/models/model_roundtrip_test.dart` — 38 tests covering `fromJson`/`toJson` round-trips, missing-field defaults, status normalization, computed properties (`isActive`, `isDeleted`, `isMissing`, `visibleBeforeCount`, `visibleAfterCount`), optional field presence/absence in JSON output, and `copyWith` independence for all six domain models (`PhotoRecord`, `VideoRecord`, `Videos`, `JobNote`, `Unit`, `Job`). Includes schema version 1 backward-compatibility cases.
- `test/utils/unit_sorter_test.dart` — 20 tests covering type ordering (Hood → Fan → Other), natural number sort, letter-suffix sort, name normalization variations (`hood1` / `Hood 1` / `HOOD 1`), edge cases (empty list, single item, original list not mutated), and a full realistic job unit list.

All 58 tests pass.

### Phase 2: Scheduling and Management Features (complete)

**Completed:**

- `scheduledDate` (String?, YYYY-MM-DD) and `sortOrder` (int?) added to `Job` model (backward-compatible, null defaults)
- `DayNote` model at `lib/domain/models/day_note.dart` — `noteId`, `date`, `text`, `createdAt`, `status`; same immutable/fromJson/toJson/copyWith pattern as `JobNote`
- `DayNoteStore` at `lib/storage/day_note_store.dart` — reads/writes `day_notes.json` in root jobs directory
- `JobsService` additions: `setScheduledDate`, `setSortOrder`, `addDayNote`, `softDeleteDayNote`, `loadDayNotes`, `loadAllDayNotes`
- `JobsHome` redesign: day-grouped cards, shift notes section per day, job note count chips, move up/down reorder buttons within day cards
- `JobDetail` additions: schedule picker in header, read-only shift notes section, job notes inline preview (last 3 active notes)
- `JobDetailController` additions: `loadShiftNotes()`, `setScheduledDate()`
- Model and service tests updated/extended

Note: `managerNotes` and `clientInfo` deferred to Phase 3. Sync model deferred to Phase 4.

### Phase 3: Pre-Sync Architecture + Structured Photo Workflow (Steps 1-4 complete)

See Phase 3 plan document in `~/.cursor/plans/` for full implementation details.

**Completed (Steps 1-4):**

- Step 1: Data model updates — `subPhase` on `PhotoRecord`, `completedAt` + `isComplete` on `Job`, `visibleCount(phase, subPhase)` on `Unit`, `UnitPhaseConfig` utility class, schema version bumped to 3, 26 new model tests (84 total model tests)
- Step 2: Riverpod scaffolding — `flutter_riverpod` + `shared_preferences` dependencies, `ProviderScope` wrapping app, `JobRepository`/`DayNoteRepository` abstract interfaces, `LocalJobRepository`/`LocalDayNoteRepository` implementations, repository and service providers in `lib/providers/`
- Step 3: Core providers + JobsHome migration — `jobListProvider` (AsyncNotifier), `dayNotesProvider` (AsyncNotifier), `JobsHome` migrated from `StatefulWidget` to `ConsumerStatefulWidget`, manual `_loadAll`/`_isLoading`/`_results` replaced with `ref.watch`/`ref.invalidate`, `app.dart` simplified (no more manual DI)
- Step 4: JobDetail migration — `jobDetailProvider` (family AsyncNotifier parameterized by job dir path), `JobDetail` migrated to `ConsumerStatefulWidget`, `_reloadJob` uses provider invalidation, controller retained as mutation delegator

All 153 tests pass after each step.

**Remaining (Steps 5-8):**
- Step 5: Sub-phase capture UI (unit card redesign for 4-phase hood/fan, 2-phase misc)
- Step 6: Job completion logic (Mark Complete / Reopen, `completedAt` timestamp)
- Step 7: Smart day card sorting (incomplete first, upcoming, completed, unscheduled)
- Step 8: Lightweight role model (manager vs. technician device mode)

**Key decisions:**
- Hood sub-phases: Filters On / Filters Off
- Fan sub-phases: Closed / Open
- Misc: no sub-phases (Before / After only)
- Sub-phases are metadata only — filesystem and export structure unchanged
- Job completion solves the midnight-crossing problem for night shifts
- Roles are fixed per device (manager phone vs. crew phone) — no toggle
- Multi-device same-job is a key use case (up to 4 people documenting one restaurant)
- Photo sync deferred to Phase 4; phase-status visibility is the priority coordination win
- Batch photo move between units/phases deferred to post-Phase 3

### Phase 4: Cloud and Multi-Platform

- Cloud database (Firestore)
- Object storage for media (Firebase Storage)
- Authentication (Firebase Auth with role claims)
- Flutter web for management dashboard
- Sync engine: scheduling cloud-first, documentation device-first
- Photo sync across devices (post-shift or live — TBD)
- Unread note counters / alert badges
- Manager permissions enforcement on crew devices

---

# 15. Jobs Home — Day-Grouped Layout

Jobs Home uses a day-grouped layout as of Phase 2.

### Day Card Sort Order (Phase 3)

1. Days with incomplete jobs (ascending by date) — active shift stays at top until all jobs complete
2. Upcoming days with no jobs started (ascending)
3. Completed days (descending — most recently completed first)
4. Unscheduled section at the bottom

### Scheduled Jobs (Day Cards)

Jobs with a `scheduledDate` are grouped into day cards.

Each day card contains:
- Date header (formatted: "Monday, March 20, 2026")
- Shift notes section (date-level, add/delete; long-press or delete icon to remove)
- Job tiles sorted by `sortOrder` (ascending), then `createdAt` (ascending) as fallback
- Move up / move down buttons on each job tile for in-day reordering

### Unscheduled Section

Jobs with `scheduledDate == null` appear at the bottom, sorted by `createdAt` descending (newest first). No reorder controls.

### Job Tile

Each job tile shows:
- Restaurant name (no date subtitle — scheduled date context comes from the day card header)
- Note count chip (if > 0 active notes; tap → NotesScreen)
- Move up / move down icon buttons (scheduled jobs only)
- Overflow menu: Edit Job (name + scheduled date), Delete Job

---

# 16. Notes Visibility

Three distinct note types are labeled and placed to establish ownership convention before a full permissions layer exists.

### Shift Notes (DayNote)

- **Scope:** date-level
- **Intended author:** manager (logistics, crew info, arrival times)
- **Storage:** `day_notes.json` in root jobs directory
- **UI placement:** Collapsed counter + add button on each day card (Jobs Home); expand to view/delete. NOT shown on Job Detail.

### Manager Job Notes (ManagerJobNote)

- **Scope:** job-level
- **Intended author:** manager (job-specific instructions and context)
- **Storage:** `managerNotes[]` in `job.json`
- **UI placement:** Count chip on job tile (Jobs Home) and card with count on Job Detail; both navigate to ManagerNotesScreen. Supports add, edit, and soft-delete. NOT included in export.

### Field Notes (JobNote)

- **Scope:** job-level
- **Intended author:** technician (field observations during cleaning)
- **Storage:** `notes[]` in `job.json`
- **UI placement:** Accessible only via Tools → Field Notes. Included in export as `notes.txt`.

---

# 17. Field Testing Plan

Basic workflow:

1. Create job
2. Add units
3. Capture photos
4. Capture videos
5. Add notes
6. Delete media
7. Restart app
8. Verify persistence
9. Export job
10. Verify zip structure

---

# 19. Tools System

Job-level utilities are now accessed through a **Tools hub**.

Accessible via:

- Tools card on Job Detail screen
- AppBar quick-access icon

Tools screen groups features by job phase.

```
SETUP
  Pre-clean Layout

DOCUMENTATION
  Field Notes

CLOSEOUT
  Exit Videos
  Other Videos
```

---

# 20. Pre-clean Layout Gallery

Dedicated gallery for capturing equipment placement before cleaning.

Features:

- capture photos
- view photos
- delete photos
- same interaction model as other galleries

Photos stored in:

```
PreCleanLayout/
```

---

# 21. Notes Screens

### Field Notes Screen

Tech-entered field notes, accessible via:

```
Tools → Field Notes
```

Features: view, add, delete. These are the only notes included in export.

### Manager Notes Screen

Manager-entered job notes, accessible via:

- Job Notes card on Job Detail
- Note count chip on Jobs Home job tile

Features: view, add, edit, delete. NOT included in export.

---

# 22. Video Screens

Videos are now separated into two dedicated screens.

### Exit Videos

```
Videos/Exit/
```

### Other Videos

```
Videos/Other/
```

Counts are shown directly on the Tools screen.

---

# 23. Unit Card System

Units are displayed as cards. Card layout varies by unit type.

### Hood and Fan Cards (Phase 3 — 4 sub-phases)

```
Unit Name                                    ⋮
BEFORE                 AFTER
Filters On  (3) 🖼     Filters Off (2) 🖼
Filters Off (4) 🖼     Filters On  (0) 🖼
```

For fans, sub-phase labels are "Closed" / "Open".

Each sub-phase row: tappable label → rapid capture, count, gallery icon.

Before sub-phase order: Hood = Filters On then Filters Off; Fan = Closed then Open.
After sub-phase order: Hood = Filters Off then Filters On; Fan = Open then Closed.

### Misc Cards (2 phases, no sub-phases)

```
Unit Name                                    ⋮
Before (2) 🖼           After (1) 🖼
```

Sub-phases are **metadata only** (`subPhase` on `PhotoRecord`). Filesystem and export unchanged.

---

# 24. Unit Completion State

Unit-level completion has been **removed from the UI**. The relevant workflow distinction is sub-phase completion (visible via photo counts on unit cards). Job-level completion is being added in Phase 3.

---

# 25. Job Completion (Phase 3)

Jobs can be marked complete via overflow menu. `completedAt` timestamp set on completion, cleared on reopen.

Completed jobs affect day card sorting:
1. Days with incomplete jobs (ascending) — active shift stays at top
2. Upcoming days (ascending)
3. Completed days (descending — most recently completed first)
4. Unscheduled

This solves the midnight-crossing problem: the active day stays at top until all jobs are marked complete, regardless of calendar date.

---

# 26. Unit Editing

Overflow menu per unit:

```
Edit Name
Remove Unit
```

Rename updates metadata only.

Filesystem folders are not renamed.

---

# 27. Unit Removal

Units can be removed **only if they contain zero visible photos**.

Rules:

If photos exist:

```
Cannot Delete Unit
Remove unit photos first.
```

If no photos exist:

```
Remove Unit?
Cancel / Remove
```

Removal updates:

- job.json
- UI
- persists across restart

---

# 28. Smart Unit Ordering

Unit sorting is implemented in `lib/utils/unit_sorter.dart`.

`UnitSorter.sort(List<Unit>)` is the canonical implementation used for UI display, export ordering, and future upload preparation.

Sort order:

1. Hoods
2. Fans
3. Other units

Within each type group, units sort by natural number order with letter-suffix support:

```
hood 1
hood 1a
hood 2
hood 10
fryer hood
fan 1
fan 2
misc item
```

Name normalization handles:

```
hood1
hood 1
Hood 1
```

All treated as equivalent for sort purposes.

The `job_detail.dart` and `jobs_service.dart` previously contained their own private sort implementations (duplicated before this utility existed). Both have been replaced with `UnitSorter.sort()`. The sort logic is now covered by automated tests.

---

# Current Stability Assessment

Architecture: **9 / 10**
Data integrity: **9 / 10**
Workflow clarity: **9 / 10**
Field readiness: **9 / 10**

Core field documentation workflow is complete. Phase 1 and Phase 2 are complete. Phase 3 Steps 1-4 are complete (architecture half).

Next priority: Phase 3 Steps 5-8 (feature half — sub-phase UI, job completion, smart sorting, role model).

Phase 3 progress:
- Step 1: Data model updates (`subPhase`, `completedAt`, `UnitPhaseConfig`, schema v3): **complete**
- Step 2: Riverpod scaffolding + repository interfaces: **complete**
- Step 3: Core providers + JobsHome Riverpod migration: **complete**
- Step 4: JobDetail Riverpod migration: **complete**
- Step 5: Sub-phase capture UI: **pending**
- Step 6: Job completion logic: **pending**
- Step 7: Smart day-card sorting: **pending**
- Step 8: Lightweight role model: **pending**

New files added in Phase 3 (Steps 1-4):
- `lib/domain/models/unit_phase_config.dart` — sub-phase metadata utility
- `lib/data/repositories/job_repository.dart` — abstract interface
- `lib/data/repositories/local_job_repository.dart` — filesystem implementation
- `lib/data/repositories/day_note_repository.dart` — abstract interface
- `lib/data/repositories/local_day_note_repository.dart` — filesystem implementation
- `lib/providers/repository_providers.dart` — Riverpod providers for repositories + storage
- `lib/providers/service_providers.dart` — Riverpod provider for JobsService
- `lib/providers/job_list_provider.dart` — AsyncNotifier for all scanned jobs
- `lib/providers/day_notes_provider.dart` — AsyncNotifier for all day notes
- `lib/providers/job_detail_provider.dart` — family AsyncNotifier for single job