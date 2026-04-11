# KitchenGuard — UI Structure

---

# Jobs Home Screen

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

---

# Job Detail Screen

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
- Camera icon (leading) → opens rapid capture tagged with that sub-phase
- Tappable label+count → opens gallery filtered to that sub-phase
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

# Rapid Capture Architecture

KitchenGuard includes a **persistent rapid capture camera system**.

The goal is to support **high-speed field documentation** without repeated camera open/confirm cycles.

Rapid capture behavior:

```
open camera
↓
tap capture
↓
photo saved immediately
↓
camera stays open
↓
repeat
```

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

### Portrait Lock

Camera UI is locked to portrait orientation.

Reason: Technicians frequently move and tilt phones while working around equipment. Preventing UI rotation improves stability and tap accuracy.

### Capture Feedback

Two forms of feedback occur after capture:

1. brief flash overlay
2. light haptic feedback

These mimic native camera behavior and reduce uncertainty about capture success.

---

# Camera Performance Principles

Rapid capture must prioritize:

```
speed
reliability
low latency
```

Preferred configuration:

```
ResolutionPreset.medium
ImageFormatGroup.jpeg
```

High-resolution capture is unnecessary for hood cleaning documentation.

Smaller images:

- write faster
- export faster
- reduce storage pressure
- improve capture throughput

---

# Video Capture Screen

KitchenGuard includes a **persistent video capture screen** using the `camera` package directly (not `ImagePicker`).

Video capture behavior:

```
open camera
↓
tap record (red circle)
↓
recording starts (live duration timer)
↓
tap stop (red rounded square)
↓
video saved, camera stays open
↓
repeat or navigate back
```

This is used for:

- Exit videos
- Other videos

Design goals:

- `ResolutionPreset.high` with `enableAudio: true`
- Clear start/stop recording controls (red circle → red square)
- Live recording duration display (MM:SS in red)
- "Saved" inline status after each recording
- `PopScope` prevents accidental back navigation while recording or saving
- Camera stays open for multiple recordings

The screen follows the same layout pattern as `RapidPhotoCaptureScreen`: empty AppBar, title + count header, expanded camera preview, bottom controls.

Key files:

```
lib/presentation/screens/video_capture_screen.dart              — VideoCaptureScreen widget
lib/presentation/controllers/job_detail_controller.dart         — captureVideoFromFile() method
lib/presentation/job_detail.dart                                — wiring (exit + other video flows)
```
