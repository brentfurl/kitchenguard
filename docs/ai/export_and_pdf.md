# KitchenGuard — Export and PDF

---

# ZIP Export Behavior

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

Export uses in-memory `Archive` + `ZipEncoder` (not `ZipFileEncoder`, which has a silent data-loss bug in archive 4.x). Files are read as bytes and added to an `Archive` object, then the complete archive is encoded and written to disk in one shot.

**Cloud download fallback:** after adding local files to the archive, the export iterates all active unit photos and videos from `job.json`. Any whose `relativePath` was not found on disk are downloaded from Firebase Storage via `FirebaseStorage.instance.ref('jobs/{jobId}/{relativePath}').getData()` and added to the archive. Download failures are skipped silently. This ensures the export includes all media regardless of which device captured it.

---

# PDF Photo Report

Both mobile and web offer a structured PDF photo report.

## PDF Structure

- **Cover page**: "KitchenGuard", restaurant name, address (if entered), shift date
- **Section pages**: one section per unit + phase (e.g., "Hood 1: Before", "Hood 1: After")
- **Layout**: Letter portrait, 2 columns x 3 rows (6 photos per page)
- Sections start on a new page; if >6 photos, the section continues on the next page with the title repeated
- Photos are same size regardless of how many per page (empty cells left blank)
- Pre-clean layout photos excluded (same as ZIP)
- Videos excluded (photos only)
- Unit ordering matches ZIP export (Hoods, Fans, Misc via `UnitSorter`)
- Cloud-only photos downloaded from Firebase Storage (same fallback as ZIP)

## Export Presets

- `Original`
- `Email-friendly (fast)` (single-pass, best-effort)
- `Email-friendly (5 MB, slower)` (strict target with bounded adaptive attempts)

Web default preset is `Email-friendly (fast)` for better runtime. Mobile shows a preset picker bottom sheet before share.

## Implementation

Uses the `pdf` package (pure Dart, platform-independent). The builder (`PdfExportBuilder`) is shared by both web and mobile export flows. Compression uses `package:image` via `PdfImageOptimizer`.

## Key Files

```
lib/services/pdf_export_builder.dart           — shared PDF builder (cover + 2x3 grid sections)
lib/services/pdf_export_preset.dart            — preset definitions (Original, Email fast, Email 5MB)
lib/services/pdf_image_optimizer.dart          — bounded adaptive image compression and PDF build orchestration
lib/web/web_pdf_export_service.dart            — web: concurrent photo download + preset-aware PDF build + browser download
lib/web/screens/web_job_detail_screen.dart     — web PDF preset selector (default: Email fast) + progress UI
lib/application/jobs_service.dart              — mobile/local PDF export path with preset-aware build
lib/presentation/job_detail.dart               — mobile PDF preset bottom sheet before share
```

---

# Web ZIP Export

`WebExportService` collects all active photos/videos with a `cloudUrl`, downloads bytes via `XMLHttpRequest`, builds an in-memory ZIP using `package:archive` (`Archive` + `ZipEncoder`), and triggers a browser file download via `package:web` (`Blob` + `URL.createObjectURL` + anchor click).

ZIP structure mirrors mobile export. Progress indicator shows during download; skipped items (no cloudUrl) reported to user. Videos with missing `cloudUrl` are resolved from Firebase Storage before downloading.

---

# Web Video Download

Per-video download menu in web job detail with two options:
- `Download (~10 MB)` — calls `prepareCompressedVideoDownload` backend callable (ffmpeg transcoding), then downloads the result
- `Download original` — direct download from Firebase Storage

The callable function (`functions/index.js`) handles:
- If source <= target size: returns original path
- Otherwise: downloads, probes with ffprobe, transcodes with ffmpeg (adaptive bitrate), uploads compressed result, returns metadata

Web callable timeout set to 8 minutes for longer transcodes.

---

# Export Key File

```
lib/application/jobs_service.dart              — mobile exportJobZip (Archive + ZipEncoder + cloud fallback)
lib/web/web_export_service.dart                — web ZIP export (HTTP download + in-memory archive + browser trigger)
functions/index.js                             — prepareCompressedVideoDownload callable
```
