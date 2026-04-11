# KitchenGuard — Web Console

---

# Flutter Web Management Dashboard

The web dashboard is a separate Flutter web app served from the same codebase using conditional imports. It provides schedule management, photo review, and user management for managers — no local filesystem access.

---

# Platform Separation

`main.dart` uses two conditional imports to cleanly separate mobile and web code paths:

```
lib/app_entry.dart              — conditional export: app.dart (mobile) vs web/web_app.dart (web)
lib/main_mobile.dart            — Workmanager init (native only)
lib/main_web.dart               — no-op (web has no background tasks)
```

The mobile code path (`app.dart` → `JobsHome` → filesystem repos) is never compiled on web. The web code path (`web/web_app.dart` → `WebDashboard` → Firestore-only repos) is never compiled on native. This avoids `dart:io` compilation errors on web.

---

# Web Architecture

```
Web App
  ├─ Auth gate (shared AuthScreen + role picker)
  ├─ Manager-only access check (technicians see "Access Restricted")
  └─ WebDashboard (sidebar navigation)
       ├─ Schedule — jobs grouped by date, create/edit/delete, day notes/schedules
       │    ├─ Multi-select filter row (Today | Upcoming | Past | Unscheduled | Published)
       │    ├─ Day card: clickable shift notes chip (add/edit/delete via WebNotesDialog)
       │    ├─ Job tile: clickable job notes chip (add/edit/delete via WebNotesDialog)
       │    └─ Drag-to-reorder jobs within dates (ReorderableListView)
       ├─ Users — user list from Firestore `users` collection, role assignment
       └─ Job Detail (drill-in from schedule, filter state preserved via Offstage)
            ├─ Job metadata (address, access info)
            ├─ Clickable note chips: "N job notes" + "N field notes" (always visible, open CRUD dialogs)
            ├─ Photo review (grid, Firebase Storage URLs via Image.network + status indicators)
            ├─ Video list (upload status, cloud URLs, per-video download menu)
            ├─ Download ZIP button (in-memory archive from cloud URLs, browser download)
            └─ Download PDF button (preset selector: Original, Email fast, Email 5MB)
```

---

# Web Providers

Web-specific providers in `lib/web/web_providers.dart` use Firestore directly (no filesystem):

- `webJobRepositoryProvider` → `WebJobRepository` (Firestore-only CRUD, real-time streams)
- `webJobListProvider` → `StreamProvider<List<Job>>` (real-time job list)
- `webDayNoteRepositoryProvider` → `CloudDayNoteRepository` (reused from mobile)
- `webDayScheduleRepositoryProvider` → `CloudDayScheduleRepository` (reused from mobile)
- `webUsersProvider` → real-time stream from Firestore `users` collection
- `webAuthServiceProvider` → `AuthService` (shared with mobile)

Auth providers (`authStateProvider`, `appRoleProvider`) are shared between mobile and web since they only depend on Firebase Auth (no `dart:io`).

---

# Web Job Repository

`WebJobRepository` uses Firestore `update()` for partial field edits to avoid overwriting documentation data (photos, videos) that mobile devices may have written since the web's last read.

- `saveJob()` — full doc `set()`, used only for new job creation
- `updateFields()` — Firestore `update()` for specific fields only:
  - Reorder → `sortOrder`
  - Mark Complete / Reopen → `completedAt`
  - Edit Job dialog → scheduling fields
  - Note CRUD → `managerNotes` or `notes`
  - Video retry → `videos`

Uses `FieldValue.delete()` for nullable fields being cleared.

---

# Web Notes

Reusable `WebNotesDialog` widget (`lib/web/widgets/web_notes_dialog.dart`) handles CRUD for all note types:
- Shift notes on day cards (saved via `CloudDayNoteRepository`)
- Job notes on job tiles and job detail (saved via `WebJobRepository.updateFields`)
- Field notes in job detail (saved via `WebJobRepository.updateFields`)

---

# Day Publishing

Managers can publish/unpublish days to control visibility for technicians.

- Published filter chip in web console (mutually exclusive with other filters, restricted to Today + Upcoming)
- Unpublished days show "DRAFT" badge for managers
- Technicians see only published days (filtered after date classification)

---

# Deployment

Firebase Hosting configured in `firebase.json` (public: `build/web`). Deploy with:

```
flutter build web
firebase deploy --only hosting
```

---

# User Management

The Firestore `users` collection stores user profiles (email, displayName, role, lastLoginAt). Entries are created/updated:
1. On web sign-in (`_WebAuthGate._ensureUserDoc()`)
2. On role assignment (`setUserRole` Cloud Function mirrors role to Firestore)

Managers can view all users and change roles from the web dashboard.

---

# Key Web Files

```
lib/app_entry.dart                               — conditional export (mobile vs web)
lib/main_mobile.dart                             — mobile platform init (Workmanager)
lib/main_web.dart                                — web platform init (no-op)
lib/web/web_app.dart                             — web MaterialApp + auth gate (manager-only)
lib/web/web_dashboard.dart                       — sidebar navigation shell (Offstage preserves state)
lib/web/web_providers.dart                       — web-specific Riverpod providers
lib/web/web_job_repository.dart                  — Firestore-only job CRUD + updateFields + real-time streams
lib/web/screens/web_schedule_screen.dart         — schedule management (job CRUD, day cards, filters, drag reorder, note dialogs)
lib/web/screens/web_job_detail_screen.dart       — photo review + job detail + ZIP/PDF download + note CRUD + video download
lib/web/screens/web_users_screen.dart            — user management + role assignment
lib/web/widgets/web_notes_dialog.dart            — reusable notes CRUD dialog (shared by schedule + detail)
lib/web/web_export_service.dart                  — web ZIP export (HTTP download + in-memory archive + browser trigger)
lib/services/pdf_export_builder.dart             — shared PDF builder (cover + 2x3 grid sections)
lib/web/web_pdf_export_service.dart              — web PDF export (concurrent download + preset-aware build + browser download)
```
