# KitchenGuard — Data Model

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
 ├ clientId           (String?, nullable — reserved for future Client entity)
 ├ schemaVersion      (integer, current = 3)
 ├ units[]
 ├ preCleanLayoutPhotos[]
 ├ notes[]            (field notes — tech-entered, included in export)
 ├ managerNotes[]     (manager job notes — NOT included in export)
 └ videos
      ├ exit[]
      └ other[]
```

New fields (address, city, accessType, accessNotes, hasAlarm, alarmCode, hoodCount, fanCount, clientId) are all nullable and backward-compatible — omitted from JSON when null, defaulting to null on read. Schema version remains 3.

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
syncStatus           (String?, 'pending'|'uploading'|'synced'|'error'; Step 4a addition)
cloudUrl             (String?, Firebase Storage download URL; Step 4a addition)
uploadedBy           (String?, uploader's UID; Step 4a addition)
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
syncStatus           (String?, 'pending'|'uploading'|'synced'|'error'; Step 4a addition)
cloudUrl             (String?, Firebase Storage download URL; Step 4a addition)
uploadedBy           (String?, uploader's UID; Step 4a addition)
```

Visible photos exclude:

- deleted
- missing_local

UI counts always reflect **visible photos only**.

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

`DaySchedule` fields: `date` (YYYY-MM-DD), `shopMeetupTime` (String?, HH:mm), `firstRestaurantName` (String?), `firstArrivalTime` (String?, HH:mm), `published` (bool?, null = draft), `publishedAt` (String?, ISO 8601 UTC), `publishedBy` (String?, Firebase UID). All optional fields omitted from JSON when null. Empty schedules (all nulls and not published) are removed from the file.

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
