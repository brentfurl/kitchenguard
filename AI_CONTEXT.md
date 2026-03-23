# KitchenGuard — AI Context

This file provides persistent context for AI tools assisting development.

The goal is to keep AI suggestions aligned with the architecture and product goals.

---

# Project Purpose

KitchenGuard is a **Flutter-based field documentation app** used by technicians cleaning commercial kitchen hood systems.

The app captures structured documentation during cleaning jobs and exports the documentation as organized media packages.

Primary design goals:

- offline-first
- reliable in field environments
- fast to use during active work
- structured documentation

---

# Core Workflow

Technician workflow:

1. Create job
2. Capture **Pre-clean Layout** photos
3. Add units (hoods, fans, misc)
4. Capture **Before** photos
5. Perform cleaning
6. Capture **After** photos
7. Add notes if needed
8. Capture exit video
9. Export job documentation

The interface should prioritize **speed and clarity**.

---

# Key Architectural Principle

KitchenGuard is **offline-first**.

The **local filesystem + job.json** is the **source of truth**.

Future sync systems must **layer on top** of this model, not replace it.

---

# Storage Model

Jobs are stored locally:

```
/data/data/<package>/app_flutter/KitchenCleaningJobs/
```

Example job folder:

```
Restaurant_2026_03_06/
    job.json

    PreCleanLayout/

    Hoods/
        hood_1__unit-xxxx/
            Before/
            After/

    Fans/
    Misc/

    Videos/
        Exit/
        Other/
```

Key rules:

- media files live inside job folder
- job.json tracks metadata only
- file paths are resolved using **relativePath**

Never reconstruct paths from names.

---

# job.json Structure

```
job
 ├ jobId              (UUID v4)
 ├ restaurantName
 ├ shiftStartDate
 ├ scheduledDate      (String?, YYYY-MM-DD, null = unscheduled)
 ├ sortOrder          (int?, null = unset; 0-based within a day)
 ├ createdAt
 ├ updatedAt          (bumped on every write)
 ├ completedAt        (String?, ISO 8601 UTC, null = not complete)
 ├ address            (String?, nullable)
 ├ city               (String?, nullable)
 ├ accessType         (String?, no-key / get-key-from-shop / key-hidden / lockbox)
 ├ accessNotes        (String?, lockbox code or key description)
 ├ hasAlarm           (bool?, nullable)
 ├ alarmCode          (String?, nullable)
 ├ hoodCount          (int?, nullable)
 ├ fanCount           (int?, nullable)
 ├ schemaVersion      (integer, current = 3)
 ├ units[]
 ├ preCleanLayoutPhotos[]
 ├ notes[]            (field notes — tech-entered, included in export)
 ├ managerNotes[]     (manager job notes — NOT included in export)
 └ videos
      ├ exit[]
      └ other[]
```

New fields (address, city, accessType, accessNotes, hasAlarm, alarmCode, hoodCount, fanCount) are all nullable and backward-compatible — omitted from JSON when null, defaulting to null on read. Schema version remains 3.

Each unit contains:

```
unitId               (UUID v4)
type
name
unitFolderName
isComplete
completedAt
photosBefore[]
photosAfter[]
```

---

# Media Metadata

Photo entries include:

```
photoId              (UUID v4)
fileName
relativePath
capturedAt
status
missingLocal
recovered
deletedAt
subPhase             (String?, null for misc; Phase 3 addition)
```

`subPhase` values by unit type:
- Hood: `filters-on`, `filters-off`
- Fan: `closed`, `open`
- Misc: null (no sub-phases)

Video entries include:

```
videoId              (UUID v4)
fileName
relativePath
capturedAt
status
deletedAt
```

Visible photos exclude:

- deleted
- missing_local

UI counts always reflect **visible photos only**.

---

# Current UI Structure

## Jobs Home Screen

Day-grouped layout with filter row at top. Jobs with a `scheduledDate` appear in day cards sorted chronologically. Jobs without a `scheduledDate` appear in an "Unscheduled" section (visible when the Unscheduled filter is active).

```
Filter Row (Today | Upcoming | Past | Unscheduled) — default: Today + Upcoming

Day Card (date header + shift notes counter chip + TODAY badge)
  └─ Arrival Times section (shop meetup + first restaurant arrival from DaySchedule)
  └─ Stitch-style job sub-cards (drag-reorderable via ReorderableListView)
       └─ Bold restaurant name
       └─ Address (smaller, below name)
       └─ Access type icon + label, unit counts ("N hoods, N fans")
       └─ Drag handle + overflow menu: Edit Job, Mark Complete, Delete Job

Unscheduled Section
  └─ Simple job tiles (sorted by createdAt desc)
```

### Create / Edit Job Dialog (shared two-tier design)

Top section (always visible):
- Restaurant name (text field, required)
- Scheduled date (date picker, optional)

Expandable sections:
- **Address** — street address + city
- **Access Info** — access type dropdown (no-key, get-key-from-shop, key-hidden, lockbox), conditional text field for key-hidden/lockbox, alarm toggle + alarm code
- **Contacts** — quick-add entries saved as manager notes
- **Units** — hood count + fan count (auto-creates units on job creation)

Edit dialog pre-fills all fields; clear flags handle removal.

## Job Detail Screen

```
Header
  ├─ Restaurant name (headline)
  ├─ Address (smaller, below name)
  ├─ Access info (icon + type + notes + alarm indicator)
  ├─ Complete badge (if applicable)
  └─ Two note counters at right: "N job notes" | "N field notes" (always visible, tappable)
↓
Promoted Tools row: [Pre-clean Layout (N)] [Exit Video (N)]
↓
Units section title
↓
Unit cards (scrollable list)
```

AppBar tools dropdown (handyman icon → PopupMenuButton):
- Field Notes (count)
- Other Videos (count)

Schedule picker removed from Job Detail — scheduling handled from Jobs Home only.

---

# Unit Cards

Units appear as cards. Card layout varies by unit type.

### Hood and Fan Cards (4 sub-phases)

```
Unit Name                                    ⋮
BEFORE                 AFTER
Filters On  (3) 🖼     Filters Off (2) 🖼
Filters Off (4) 🖼     Filters On  (0) 🖼
```

For fans, sub-phase labels are "Closed" / "Open" instead of "Filters On" / "Filters Off".

Each sub-phase row has:
- Tappable label → opens rapid capture tagged with that sub-phase
- Photo count (visible/active only)
- Gallery icon → opens gallery filtered to that sub-phase

Before sub-phase order:
- Hood: Filters On, then Filters Off
- Fan: Closed, then Open

After sub-phase order:
- Hood: Filters Off, then Filters On
- Fan: Open, then Closed

### Misc Cards (2 phases, no sub-phases)

```
Unit Name                                    ⋮
Before (2) 🖼           After (1) 🖼
```

Same camera + gallery pattern, but no sub-phase distinction.

### Sub-phase metadata

Sub-phases are **metadata only** (`subPhase` field on `PhotoRecord`). Photos are still physically stored in `Before/` and `After/` folders. Export structure is unchanged.

---

# Photo Gallery Multi-Select and Move

The unit photo gallery (`UnitPhotoBucketScreen`) supports multi-select mode.

### Entry

Long-press any photo to enter select mode. The pressed photo is auto-selected. Subsequent taps toggle selection.

### Actions in select mode

AppBar transforms to show:
- Close (X) button to exit
- Selected count
- Remove (delete icon) — batch soft-delete with confirmation
- Move (drive_file_move icon) — opens move destination sheet

### Move destination sheet

A bottom sheet that lets the user pick a target unit (and optionally a sub-phase):
- Units grouped by type (Hoods, Fans, Misc)
- Current unit labeled "(current)"
- Same phase assumed (Before stays Before)
- Sub-phase chips appear for hood/fan units (default matches current sub-phase if possible)
- "Move here" button disabled until a valid destination is selected

### Move behavior

- **Same-unit move** (sub-phase change): only updates `PhotoRecord.subPhase` metadata — no file I/O
- **Cross-unit move**: physically relocates files on disk, updates `relativePath` and `subPhase`, saves job.json
- Phase changes (Before to After) are not supported in this iteration

### Key files

- `lib/presentation/screens/unit_photo_bucket_screen.dart` — multi-select gallery
- `lib/presentation/widgets/move_destination_sheet.dart` — destination picker
- `lib/application/jobs_service.dart` — `movePhotos()` method
- `lib/presentation/controllers/job_detail_controller.dart` — `movePhotos()` delegation

---

# Unit Editing

Unit overflow menu includes:

```
Edit Name
Remove Unit
```

Rename changes metadata only.

Filesystem folders are **not renamed**.

---

# Unit Removal Rules

Units can only be removed if:

```
Before count = 0
After count = 0
```

If photos exist:

```
Cannot Delete Unit
Remove photos first.
```

If no photos exist:

```
Remove Unit?
Cancel / Remove
```

Removal updates:

- UI
- job.json
- persists across restart

---

# Export Behavior

Export generates:

```
KitchenGuard_<Restaurant>_<Timestamp>.zip
```

Contains:

```
job.json
Hoods/
Fans/
Misc/
Videos/
notes.txt (optional — field notes only)
```

Pre-clean layout photos are **excluded**. Manager job notes are **excluded** from export (only field notes appear in `notes.txt`).

---

# Planned Improvements

### Smart Unit Sorting

Units should display in workflow-friendly order.

```
Hoods
Fans
Other
```

Examples:

```
hood 1
hood 2
hood 10
fryer hood
fan 1
fan 2
misc item
```

Sorting must normalize variations:

```
hood1
hood 1
Hood 1
```

The same sorting helper should be used for:

- UI display
- export ordering
- database uploads

---

# AI Assistance Guidelines

When suggesting changes:

- prefer incremental improvements
- avoid risky storage changes
- do not break relativePath rule
- keep filesystem model intact
- prioritize field usability
- all domain data must use typed model classes, not raw maps
- all new entities must use UUID v4 for IDs
- respect the two-domain split (scheduling vs. documentation)
- all data access in `JobsService` goes through repository interfaces (not raw stores)

When proposing code:

- keep explanations concise
- avoid unnecessary abstractions
- avoid large refactors unless requested
- use the existing `JobNote` pattern for new model classes
- ensure `fromJson` handles missing fields gracefully for backward compatibility

## ---------------------------------------

# Rapid Capture Architecture

KitchenGuard now includes a **persistent rapid capture camera system**.

The goal is to support **high-speed field documentation** without repeated camera open/confirm cycles.

Rapid capture behavior:


open camera
↓
tap capture
↓
photo saved immediately
↓
camera stays open
↓
repeat


This is used for:

- Unit Before photos
- Unit After photos
- Pre-clean Layout photos

Design goals:

- minimal capture latency
- clear feedback on save
- minimal technician interaction per photo

---

# Capture UX Rules

Rapid capture screens include several usability safeguards.

### Portrait Lock

Camera UI is locked to portrait orientation.

Reason:

Technicians frequently move and tilt phones while working around equipment.

Preventing UI rotation improves stability and tap accuracy.

---

### Capture Feedback

Two forms of feedback occur after capture:

1. brief flash overlay
2. light haptic feedback

These mimic native camera behavior and reduce uncertainty about capture success.

---

# Camera Performance Principles

Rapid capture must prioritize:


speed
reliability
low latency


Preferred configuration:


ResolutionPreset.medium
ImageFormatGroup.jpeg


High-resolution capture is unnecessary for hood cleaning documentation.

Smaller images:

- write faster
- export faster
- reduce storage pressure
- improve capture throughput

---

# Current Development Phase

**Phase 2 complete.** **Phase 3 complete** (all 8 steps). **Pre-Phase 4 UX rework complete.** **Phase 4 in progress** (Steps 0-1 complete).

Core capabilities complete:

- rapid photo capture
- structured job storage
- job-level tools
- smart unit naming
- job sorting and deletion
- export packaging
- scheduling (`scheduledDate`, `sortOrder`) on `Job`
- `DayNote` entity and `day_notes.json` storage
- `DaySchedule` entity and `day_schedules.json` storage
- day-grouped Jobs Home with filter row and arrival times
- Stitch-style job sub-cards with drag reorder
- two-tier Create/Edit Job dialog (name+date + expandable sections)
- Job Detail: address, access info, dual note counters, promoted tools
- sub-phase photo capture (4-phase hood/fan cards, 2-phase misc)
- job completion logic (Mark Complete / Reopen, `completedAt`)
- smart day-card sorting (incomplete first, completed last)
- lightweight device role model (manager / technician)
- batch photo move (multi-select gallery, move between units/sub-phases)

Phase 4 completed steps:
- Step 0: Repository plumbing — `JobsService` migrated from raw stores (`JobStore`, `ImageFileStore`, `VideoFileStore`, `DayNoteStore`, `DayScheduleStore`) to repository interfaces (`JobRepository`, `DayNoteRepository`, `DayScheduleRepository`). All data access flows through abstract interfaces, making cloud swap transparent.
- Step 1: Firebase project setup — Firebase project `kitchenguard-8e288` created, FlutterFire CLI configured for Android/iOS/Web, `firebase_core` added, `Firebase.initializeApp()` in `main.dart`.

Phase 4 remaining:
- Step 2: Firebase Auth + roles (email/password, custom claims Cloud Function, auth gate screen)
- Step 3: Firestore for scheduling data (schema design, cloud repositories, `clientId` on Job)
- Step 4: Firebase Storage + upload infrastructure (photo sync status, upload queue, background uploads)
- Step 5: Sync engine (scheduling cloud-first, documentation device-first)
- Step 6: Flutter web management dashboard

---

# DaySchedule Storage

`DaySchedule` entities are stored in `day_schedules.json` at the root of the jobs directory. One schedule per date (not a list).

```
KitchenCleaningJobs/
    day_notes.json
    day_schedules.json
    Restaurant_2026_03_06/
        job.json
        ...
```

`day_schedules.json` format:

```json
{
  "2026-03-22": {
    "date": "2026-03-22",
    "shopMeetupTime": "09:15",
    "firstRestaurantName": "Pizza Joint",
    "firstArrivalTime": "09:45"
  }
}
```

`DaySchedule` fields: `date` (YYYY-MM-DD), `shopMeetupTime` (String?, HH:mm), `firstRestaurantName` (String?), `firstArrivalTime` (String?, HH:mm). All optional fields omitted from JSON when null. Empty schedules (all nulls) are removed from the file.

---

# DayNote Storage

`DayNote` entities are stored in a separate file at the root of the jobs directory:

```
KitchenCleaningJobs/
    day_notes.json
    Restaurant_2026_03_06/
        job.json
        ...
```

`day_notes.json` format:

```json
{
  "2026-03-20": [
    {
      "noteId": "uuid-v4",
      "date": "2026-03-20",
      "text": "Arrive by 8am. Check in with manager.",
      "createdAt": "2026-03-20T12:00:00.000Z",
      "status": "active"
    }
  ]
}
```

`DayNote` fields: `noteId` (UUID v4), `date` (YYYY-MM-DD), `text`, `createdAt` (ISO 8601), `status` (`active` / `deleted`).
Computed: `isActive`, `isDeleted`.

---

# Note Type Distinction

Three distinct note types exist, clearly labeled in the UI:

**Shift Notes** (`DayNote` entity, `day_notes.json`) — date-level, manager-entered. Logistics, crew assignments, arrival times.
- Displayed as a tappable counter chip in day card header on Jobs Home (opens bottom sheet to view/add/delete)
- NOT displayed on Job Detail

**Manager Job Notes** (`managerNotes[]` on `Job`, `job.json`) — job-level, manager-entered. Job-specific instructions and context.
- Displayed as "N job notes" counter chip in Job Detail header (tappable → ManagerNotesScreen)
- Contacts are entered as manager notes from the Create/Edit Job dialog
- Supports add, edit, and soft-delete
- NOT included in export

**Field Notes** (`notes[]` on `Job`, `job.json`) — job-level, tech-entered. Field observations during cleaning.
- Displayed as "N field notes" counter chip in Job Detail header (tappable → NotesScreen)
- Also accessible via AppBar tools dropdown → Field Notes
- Included in export as `notes.txt`

All note types use the same soft-delete pattern (`status = 'deleted'`). Labeling and placement establish the ownership convention before a full role/permissions layer exists.

---

# Two-Domain Architecture

The app is evolving into a **two-domain system**:

**Scheduling and job management** — cloud-first, multi-platform, manager-driven.

- Manager creates jobs with scheduled dates
- Jobs grouped and ordered by day
- Day-level notes and manager notes for crew
- Eventually accessible via web for desktop management

**Field documentation** — offline-first, mobile-only, technician-driven.

- Technician captures photos, videos, and field notes
- Local filesystem remains source of truth for captured media
- Documentation syncs to cloud when connectivity allows

Both domains share the `Job` entity but have opposite data-flow directions:

- Manager pushes scheduling data down to devices
- Technicians push documentation data up to the cloud

The job model must cleanly separate scheduling fields from documentation fields.

---

# Typed Data Models

All domain entities must have **typed Dart model classes** in `lib/domain/models/`.

Model pattern (same as existing `JobNote`):

- immutable fields
- `fromJson` factory constructor
- `toJson` method
- `copyWith` method
- defensive parsing (null-safe defaults in `fromJson`)

Required model classes:

```
Job
Unit
PhotoRecord
VideoRecord
Videos (helper for exit/other lists)
JobNote (field notes — tech-entered)
ManagerJobNote (manager job notes — manager-entered)
DayNote (date-level shift notes)
DaySchedule (date-level shift timing)
```

All domain data must flow through these models. No raw `Map<String, dynamic>` access for job/unit/photo/video data outside the storage layer.

---

# ID Strategy

All entities use **UUID v4** for unique identification.

| Entity | ID field | Format |
|--------|----------|--------|
| Job | jobId | UUID v4 |
| Unit | unitId | UUID v4 |
| Photo | photoId | UUID v4 |
| Video | videoId | UUID v4 |
| Note | noteId | UUID v4 |

UUID v4 is required because:

- jobs and units will be created on multiple devices and platforms
- microsecond-based IDs can collide across devices
- UUIDs are safe for sync, merge, and conflict resolution

Existing jobs without UUIDs on photos/videos get IDs backfilled on load via `JobScanner`.

---

# Schema Versioning

`job.json` includes a `schemaVersion` integer field.

- Version 1: implicit (no field present), original schema
- Version 2: adds `updatedAt`, `schemaVersion`, `photoId` on photos, `videoId` on videos
- Version 3 (Phase 3): adds `subPhase` on photos, `completedAt` on jobs

`JobScanner` detects missing `schemaVersion` and treats it as version 1. The `Job.fromJson` factory handles migration by generating missing IDs on load. Existing photos without `subPhase` are treated as uncategorized (null).