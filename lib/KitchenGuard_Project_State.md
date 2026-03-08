# KitchenGuard — Project State Snapshot (Field-Ready v1)

## 1. Project Overview

**App Name:** KitchenGuard
**Platform:** Flutter (Android primary, iOS planned)

**Primary Use:**
Field technicians capturing cleaning documentation for restaurant hood systems.

**Core data captured:**

* Jobs (restaurant + shift date)
* Units (hoods, fans, misc)
* Before / After photos
* Exit videos
* Other videos
* Job notes
* Pre-clean layout photos

**Primary goal right now:**
Reliable **field-ready offline documentation tool** for technicians.

The app prioritizes:

* offline-first storage
* reliability in field conditions
* simple workflows for technicians

---

# 2. Architecture

The app uses a layered architecture.

```
UI (screens)
    ↓
Controller (job_detail_controller.dart)
    ↓
Service Layer (jobs_service.dart)
    ↓
Storage Layer
    - job_store.dart
    - image_file_store.dart
    - video_file_store.dart
    - job_scanner.dart
```

## Responsibilities

### UI

* Display jobs
* Capture photos/videos
* Add notes
* Export job
* Navigate between screens

### Controller

* Coordinate UI + services
* Provide computed counts
* Resolve file paths
* Manage job reloads

### Services

Business logic:

* Persist metadata
* Soft deletes
* Export generation

### Storage

Handles filesystem interaction:

* File writes
* Job JSON read/write
* Startup integrity scanning

---

# 3. Storage Model

All jobs stored locally on device.

```
/data/data/<package>/app_flutter/KitchenCleaningJobs/
```

Example job structure:

```
KitchenCleaningJobs/
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

* Jobs are **self-contained folders**
* Media files live inside the job folder
* `job.json` tracks metadata only

---

# 4. job.json Schema

Example structure:

```json
{
  "jobId": "job-...",
  "restaurantName": "Json test",
  "shiftStartDate": "2026-03-06",
  "createdAt": "...",

  "units": [
    {
      "unitId": "...",
      "type": "hood",
      "name": "hood 1",
      "unitFolderName": "hood_1__unit-177...",
      "photosBefore": [],
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

## Photo entry structure

```json
{
  "fileName": "...jpg",
  "relativePath": "Hoods/.../Before/...jpg",
  "capturedAt": "...",
  "status": "local | deleted | missing_local",
  "missingLocal": false
}
```

---

# 5. Pre-clean Layout Feature

**Purpose**

Capture reference photos of kitchen equipment layout **before moving items for cleaning**.

Technicians use these photos to restore equipment placement after the job.

**Important characteristics**

* Job-level gallery
* Before-only reference photos
* Can be taken anytime during the job
* Created automatically when job is created
* Exists as a reminder for technicians

**Storage**

```
PreCleanLayout/
    pre_clean_layout_*.jpg
```

**Metadata field**

```
preCleanLayoutPhotos[]
```

---

# 6. Important Design Rules (Current)

## 1️⃣ File resolution rule

Every photo/video must resolve using:

```
File(p.join(jobDir.path, relativePath))
```

Never reconstruct file paths from:

* unit names
* unit types
* folder guesses

**relativePath is authoritative.**

---

## 2️⃣ Unit folder naming rule

Media folders use:

```
<unitNameSanitized>__<unitId>
```

Example:

```
hood_1__unit-177...
```

Double underscore separates name and ID.

---

## 3️⃣ Soft delete rule

Deleted media:

```
status = "deleted"
```

Behavior:

* hidden from UI
* file remains on disk
* metadata preserved

---

## 4️⃣ Missing media rule

Missing only if:

```
!File(jobDir + relativePath).exists()
```

This logic was recently corrected.

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

Zip contents:

```
job.json
Hoods/
Fans/
Misc/
Videos/
notes.txt (optional)
```

**Important**

Pre-clean layout photos are **NOT included in export**.

These are operational reference photos, not compliance documentation.

---

## notes.txt generation

Created only during export.

Example:

```
Notes
Restaurant: Test_Restaurant
Shift: 2026-03-06

- needs grease pillow
- didn't relight pilot lights
```

Rules:

* chronological order
* no timestamps
* omitted if no notes

---

# 8. Photo UI Behavior

Photo grids:

* show only active photos
* hide deleted
* hide missing_local

Counts reflect **visible photos only**.

---

# 9. Camera Configuration

Using `image_picker`.

Rear camera forced:

```
preferredCameraDevice: CameraDevice.rear
```

Used for:

* `pickImage()`
* `pickVideo()`

---

# 10. Known Limitations

## Photo capture workflow

Current flow:

1. Open camera
2. Take photo
3. Confirm
4. Return to app

Not optimized for rapid capture.

Future improvement:

Use `camera` package for persistent capture mode.

---

## Emulator share bug

`share_plus` may throw:

```
PlatformException: Reply already submitted
```

Occurs on emulator only.

Works correctly on real devices.

---

# 11. Version Control Status

Git integration planned but not fully used.

Codebase stable enough to commit **baseline snapshot soon**.

---

# 12. Field Testing Plan

Test flow:

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

# 13. Next Development Focus (Before Monday Demo)

Priority: **UI/UX polish and workflow clarity**

Focus areas:

### Job Detail Screen

Add **job-level action buttons**:

* Pre-clean layout
* Notes
* Exit videos
* Other videos

Goal: reduce clutter and keep units as the main workflow.

---

### Pre-clean Layout Screen

Dedicated gallery screen.

Features:

* photo grid
* capture button
* photo count
* empty state reminder

---

### Notes Screen

Move notes off the main screen.

Notes accessible through a **Notes button**.

---

### Visual polish

Improve:

* spacing
* button clarity
* consistent section structure
* empty states

---

# 14. Longer-Term Product Direction

KitchenGuard expected to evolve into a broader system including:

* Field technician mobile app
* Manager dashboard
* Owner reporting
* QA review system
* Job assignment workflow
* Multi-user collaboration

---

# 15. Future Sync Architecture (Not Yet Implemented)

Possible approaches:

### Option A

Google Drive sync layer.

### Option B

Remote database + object storage.

Both must preserve the rule:

```
Local filesystem + job.json remain the offline source of truth.
```

---

# 16. Engineering Principle

**Offline-first architecture**

The local job folder + job.json is the **source of truth**.

Future sync systems must layer on top without breaking this invariant.

---

# 17. Current Stability Assessment

Architecture: **8.5 / 10**
Data integrity: **9 / 10**
Field readiness: **8 / 10**

Core system is stable.

Remaining work is primarily **UX polish**.

---

# 18. Immediate Task (Next Session)

Add **Pre-clean layout** feature.

Implementation goals:

* job-level photo gallery
* created when job is created
* accessible via button on Job Detail screen
* dedicated gallery screen
* uses existing photo metadata model
* stored in `PreCleanLayout/`
* tracked in `preCleanLayoutPhotos`
* excluded from export zip

Secondary improvement:

Move **Notes** to button-based screen to reduce clutter.

 


 # KitchenGuard — Job Detail Screen Layout (v1 UI Structure)

```
---------------------------------------------------
| Restaurant Name                                 |
| Shift Date                                      |
---------------------------------------------------

JOB ACTIONS
---------------------------------------------------
| [ Pre-clean Layout (3) ]                        |
|                                                 |
| [ Notes (2) ]                                   |
|                                                 |
| [ Exit Videos (1) ]                             |
|                                                 |
| [ Other Videos (0) ]                            |
---------------------------------------------------

UNITS
---------------------------------------------------
| + Add Unit                                      |
---------------------------------------------------

| Hood 1                                          |
| Before (5)      After (3)                       |
---------------------------------------------------

| Hood 2                                          |
| Before (4)      After (4)                       |
---------------------------------------------------

| Fan 1                                           |
| Before (2)      After (1)                       |
---------------------------------------------------

| Misc Item                                       |
| Before (1)      After (1)                       |
---------------------------------------------------
```

---

# Pre-clean Layout Screen

```
---------------------------------------------------
| ← Pre-clean Layout                              |
---------------------------------------------------

| + Take Photo                                    |

---------------------------------------------------

|  □   □   □   □                                   |
|  □   □   □   □                                   |
|  □   □                                           |

(photo grid)

---------------------------------------------------

Empty state message if none:

"Take photos of equipment placement before
moving items for cleaning."
```

---

# Notes Screen

```
---------------------------------------------------
| ← Notes                                         |
---------------------------------------------------

| + Add Note                                      |

---------------------------------------------------

| - Need grease pillow                            |
| - Pilot lights were off                         |
| - Filter missing                                |
---------------------------------------------------
```

---

# Design Principles Behind Layout

### 1. Job tools separated from unit workflow

Technicians primarily interact with **units**, so unit controls remain the main focus.

Job tools (notes, videos, layout photos) sit above as secondary tools.

---

### 2. Quick visual counts

Counts show:

* progress
* captured documentation
* missing items

Example:

```
Before (5)   After (3)
```

---

### 3. Clean demo flow

A boss demo would naturally follow this order:

1. Create job
2. Open job
3. Tap **Pre-clean Layout**
4. Take reference photos
5. Add unit
6. Capture before/after photos
7. Add note
8. Export job

---

### 4. Reduced screen clutter

Moving **Notes** and **Layout photos** into buttons keeps the main screen focused on:

```
Units
Before photos
After photos
```

Which is the technician's primary task.

### 5. 
I’d also strongly consider adding a tiny **Setup / Units / Closeout** heading structure to the Job Detail screen, because that could improve clarity fast without a big rewrite.
---

# Future UX Improvements (Post-Monday)

Possible enhancements later:

* horizontal action buttons instead of vertical list
* persistent camera mode
* progress indicators per unit
* swipe-to-delete media
* quick capture button directly on unit cards
