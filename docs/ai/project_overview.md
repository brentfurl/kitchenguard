# KitchenGuard — Project Overview

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

# Two-Domain Architecture

The app is a **two-domain system**:

**Scheduling and job management** — cloud-first, multi-platform, manager-driven.

- Manager creates jobs with scheduled dates
- Jobs grouped and ordered by day
- Day-level notes and manager notes for crew
- Accessible via web console for desktop management

**Field documentation** — offline-first, mobile-only, technician-driven.

- Technician captures photos, videos, and field notes
- Local filesystem remains source of truth for captured media
- Documentation syncs to cloud when connectivity allows

Both domains share the `Job` entity but have opposite data-flow directions:

- Manager pushes scheduling data down to devices
- Technicians push documentation data up to the cloud

The job model must cleanly separate scheduling fields from documentation fields.

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
