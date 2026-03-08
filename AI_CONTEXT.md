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

# job.json Structure (Simplified)

```
job
 ├ restaurantName
 ├ shiftStartDate
 ├ units[]
 ├ preCleanLayoutPhotos[]
 ├ notes[]
 └ videos
      ├ exit[]
      └ other[]
```

Each unit contains:

```
unitId
type
name
unitFolderName
photosBefore[]
photosAfter[]
completionState
```

---

# Media Metadata

Photo entries include:

```
fileName
relativePath
capturedAt
status
missingLocal
```

Visible photos exclude:

- deleted
- missing_local

UI counts always reflect **visible photos only**.

---

# Current UI Structure

## Job Detail Screen

```
Header
↓
Tools Card
↓
Units
```

### Tools Screen

Contains:

```
Pre-clean Layout
Notes
Exit Videos
Other Videos
```

Each opens its own screen.

---

# Unit Cards

Units appear as cards.

Structure:

```
Unit Name
Unit Type

Status Chip
Mark Complete / Incomplete

Before Button
After Button
```

Before/After buttons display counts.

Completion is a **workflow flag**, not a lock.

Users can still add photos after completion.

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
notes.txt (optional)
```

Pre-clean layout photos are **excluded**.

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

When proposing code:

- keep explanations concise
- avoid unnecessary abstractions
- avoid large refactors unless requested