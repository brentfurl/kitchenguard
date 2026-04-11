# KitchenGuard — Development History

This document is a reference log of all completed development phases, bug fixes, and feature work. Load this only when you need historical context about past changes.

---

# Phase Summary

**Phase 2 complete.** **Phase 3 complete** (all 8 steps). **Pre-Phase 4 UX rework complete.** **Phase 4 complete** (Steps 0-3, 4a-4e). **Phase 5 complete** (sync engine). **Step 6 complete** (Flutter web management dashboard). **Phase 7 complete** (real-time sync + broken-URL recovery). **Phase 0 (pre-publishing refactor) complete.** **Phase A complete** (day publishing). **Web Console Fixes complete.** **Bug Fix Round 2 complete.** **Web Console Notes complete.** **Web Console UX + Unit Card Redesign complete.** **Store Readiness (in progress).** **Video Capture Screen complete.** **Export ZIP fix complete.** **PDF Photo Report complete.** **Auth UX improvements.** **Photo sync overwrite fix complete.**

---

# Core Capabilities Complete

- rapid photo capture
- persistent video capture (camera package, start/stop recording)
- structured job storage
- job-level tools
- smart unit naming
- job sorting and deletion
- export packaging (ZIP + PDF)
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
- Firebase Auth (email/password) with auth gate and role picker
- user-level roles via Firebase custom claims (manager / technician)
- batch photo move (multi-select gallery, move between units/sub-phases)
- Firestore scheduling data (cloud repositories, hybrid wiring, security rules)
- Firebase Storage upload infrastructure (sync status fields, StorageService, UploadController)
- Flutter web management dashboard (schedule management, photo review, user management)
- real-time Firestore sync (replaced 5-min polling with `.snapshots()` listener)
- broken-URL recovery (re-queue photo uploads when cloud image load fails)
- day publishing (managers publish days to make them visible to technicians)
- web console: photo display, multi-select filters, ZIP/PDF export, CORS, video URL resolution
- web console: full note CRUD, Published filter, drag reorder, Mark Complete
- unit card redesign: camera icon (leading) + label+count opens gallery
- chronological note ordering on mobile
- PDF presets (Original, Email fast, Email 5MB) on both mobile and web
- per-video download with backend compression
- auth: forgot password, iOS share fix
- photo sync overwrite fix (web partial updates + mobile merge pushback)

---

# Phase 4 Steps

- **Step 0:** Repository plumbing — `JobsService` migrated from raw stores to repository interfaces
- **Step 1:** Firebase project setup — `kitchenguard-8e288`, FlutterFire CLI, `firebase_core`
- **Step 2:** Firebase Auth + roles — `AuthService`, auth gate, `AppRoleNotifier`, `setUserRole` Cloud Function
- **Step 3:** Firestore for scheduling — `CloudJobRepository`, `CloudDayNoteRepository`, `CloudDayScheduleRepository`, security rules, hybrid wiring
- **Step 4a:** Firebase Storage + basic upload — `StorageService`, `UploadController`, sync status fields
- **Step 4b:** Upload queue + offline persistence — `UploadQueue`, auto-enqueue, queue processor
- **Step 4c:** Background upload — workmanager, `BackgroundUploadService`, `UploadProgressNotifier`
- **Step 4d:** Multi-device coordination — `uploadedBy` attribution, `JobMerger` append-only merge
- **Step 4e:** Download and caching — `CloudAwareImage`, `VideoPlayerScreen` network support

---

# Phase 5: Sync Engine

Cloud-only job provisioning, `SyncNotifier` (auto-pull on open, periodic pull, connectivity monitoring), combined `SyncState`, offline banner, `_SyncIndicator`.

---

# Phase 6: Web Dashboard

Conditional import entry point, web-specific providers, Firestore-only `WebJobRepository`, sidebar `WebDashboard` with schedule management, photo review, user management. Firebase Hosting.

---

# Phase 7: Real-Time Sync + Broken-URL Recovery

Replaced 5-minute polling with Firestore `.snapshots()` real-time listener. Debounced 1s before merge. `CloudAwareImage` `onCloudUrlBroken` callback for re-uploading broken URLs.

---

# Post-Phase 6: Cross-Device Sync Bug Fixes

1. Job Detail stale after pull — added `pullVersionProvider`
2. Cloud-only unit folders missing — added `_provisionUnitFolders()`
3. Unit photos marked as missing_local — skip marking for photos with `cloudUrl`
4. Merge diagnostics — added `developer.log` to `JobMerger` and `CloudJobRepository`

---

# Post-Phase 7: UX Polish

1. Fast unit card counters — preserve `isActive` for photos with any `syncStatus`
2. "No jobs found" flash eliminated — show spinner until first pull completes
3. Filter row overflow on Android — compact chip sizing

---

# Post-Phase 7: Cross-Device Capture Race Fixes

1. Rapid capture filename collision — millisecond + microsecond precision + collision suffix
2. Legacy duplicate record repair — `JobScanner` deduplicates by `relativePath`
3. Concurrent unit creation duplicates — `JobMerger` coalesces semantically duplicate fresh units
4. Cross-unit move sync metadata loss — switched to `copyWith`

---

# Post-Phase 7: Deletion + Gallery Sync UX Fixes

1. Delete job cross-device propagation — prune local jobs missing from cloud snapshot
2. Persistent pending badge — count only `pending` entries
3. Remote in-flight photos "Missing" — initialize `syncStatus = 'pending'`, `CloudAwareImage` shows spinner
4. Gallery live-refresh on sync — listen to `pullVersionProvider`

---

# Note Editing + Sync

Added `updatedAt` to all note types. Merge uses LWW on `updatedAt`. Edit UI for field notes and shift notes. Real-time DayNote sync via Firestore stream.

---

# Bug Fix Round 2

1. Draft days visible to technicians — `!isManager` filter guard + real-time DaySchedule sync
2. Android filter row cutoff — compact chip sizing
3. Midnight rollover — `isEffectiveToday()` helper, sequential today logic
4. Mark Complete in web console — job tile menu + detail header
5. ListView bottom padding — 140px for FAB clearance

---

# Web Console Notes

Full CRUD for shift notes, job notes, and field notes via reusable `WebNotesDialog`. Real-time sync to mobile via existing Firestore listeners.

---

# Web Console UX + Unit Card Redesign

1. Published filter chip (mutually exclusive, Today + Upcoming only)
2. Drag-to-reorder jobs in web (ReorderableListView)
3. Unit card sub-phase row redesign (camera leading, label opens gallery)
4. Chronological note ordering on mobile

---

# Export ZIP Fix

Replaced `ZipFileEncoder` (archive 4.x data-loss bug) with in-memory `Archive` + `ZipEncoder`. Added cloud download fallback for missing local files.

---

# PDF Photo Report

Cover page + 2x3 grid sections per unit/phase. Shared `PdfExportBuilder` for web and mobile. Three presets. Concurrent image download on web.

---

# Web Video Download + Compression

Per-video download menu. Backend `prepareCompressedVideoDownload` callable (ffmpeg). Signed-URL workaround via Storage path + `getDownloadURL()`. 8-minute callable timeout.

---

# Phase 0: Pre-Publishing Refactoring

Decomposed `jobs_home.dart` from 2014 lines to ~794 lines. Extracted `job_dialog.dart`, `day_card.dart`, `job_sub_card.dart`, `shift_notes_sheet.dart`. Added `role_helpers.dart`.

---

# Phase A: Day Publishing

`DaySchedule` gains `published`, `publishedAt`, `publishedBy`. `JobsService.publishDay()` / `unpublishDay()`. Technicians see only published days. Managers see DRAFT badge.

---

# Web Console Fixes

1. Photo display — `Image.network` replaces `CachedNetworkImage`
2. Filter state preserved — `Offstage` + `Stack`
3. Unscheduled filter added
4. Multi-select filter chips
5. ZIP download from web
6. CORS deployed
7. Photo tap-to-retry fix
8. Video URL resolution from Storage

---

# Upload Reliability + Manual Video Retry (2026-04-05)

- `VideosScreen` retry upload menu
- `requeueVideoUpload` + `requeueFailedMedia`
- Web video status labels (Pending/Uploading/Failed)
- Video MIME contentType fix
- Storage rules: video limit raised to 500MB

---

# Sync Reliability Fixes (2026-04-08)

1. Connectivity-change upload trigger
2. Background task early-exit fix (`hasProcessableEntries`)
3. Periodic foreground retry timer (3 min)
4. Spinner tap-to-sync escape hatch
5. Snapshot-dropping race fix
6. Auto-recovery for exhausted retries (reset on load)
7. Per-photo sync status badge (mobile)
8. Web console video retry button
9. Merge ranking: `synced > uploading > pending > error > null`
10. Video retry menu widened to any non-synced

---

# Photo Sync Overwrite Fix (2026-04-08)

**Root cause:** `WebJobRepository.saveJob()` used `set()` which replaced entire documents, overwriting phone-uploaded photo records.

**Fix A:** `updateFields()` method using Firestore `update()` for all web edit operations.
**Fix B:** Mobile merge pushback when merged result has more records than cloud.

---

# Store Readiness (in progress)

- Bundle IDs: Android `com.kitchenguard.app`, iOS `com.brentfurl.kitchenguard`
- App name: "KitchenGuard"
- App icon: shield + camera shutter + checkmark on green
- Splash: solid primary green
- Crashlytics enabled
- iOS background task ID: `com.kitchenguard.uploadQueue`
- Build provenance label in Jobs Home AppBar

### Store Upload Status (2026-04-01)
- iOS archive uploaded, TestFlight build `1.0.0 (2)` processed
- App Store Connect record: **KitchenGuard Field**

### TestFlight Crash Hotfix (2026-04-02)
- iOS Workmanager setup aligned to plugin requirements
- `AppDelegate.swift`: `import workmanager_apple` + `registerPeriodicTask`

### Role Selection Crash Mitigation (2026-04-02)
- iOS skips Cloud Function claim assignment during role selection (temporary)
- Local role cache used as fallback

### dSYM Processing (2026-04-02)
- Crashlytics symbols uploaded for build `1.0.0 (3)`

### Remaining Manual Steps
- Privacy policy hosting
- TestFlight internal tester invitations

---

# Device Testing Prep

Firebase backend deployed to `kitchenguard-8e288`:
- Cloud Function live
- Firestore rules deployed
- Storage rules deployed

iOS build fixes:
- Info.plist: camera, microphone, photo library permissions
- UIBackgroundModes + BGTaskSchedulerPermittedIdentifiers
- iOS deployment target: 14.0
- Workmanager try-catch on init

Tested on:
- Android: Samsung Galaxy S24 Ultra (Android 16)
- iOS: iPhone (iOS 26.3)
