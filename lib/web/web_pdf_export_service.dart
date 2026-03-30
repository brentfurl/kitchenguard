import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:firebase_storage/firebase_storage.dart';
import 'package:web/web.dart' as web;

import '../domain/models/job.dart';
import '../services/pdf_export_builder.dart';
import '../utils/unit_sorter.dart';
import 'web_export_service.dart';

/// Builds and downloads a photo-report PDF from the web console.
///
/// Downloads photos from Firebase Storage, groups them by unit + phase,
/// and generates a structured PDF via [PdfExportBuilder].
class WebPdfExportService {
  static Future<WebExportProgress> exportJobPdf({
    required Job job,
    required void Function(WebExportProgress) onProgress,
  }) async {
    final sortedUnits = UnitSorter.sort(job.units);

    // Collect photo items grouped into sections.
    final sectionDefs = <_SectionDef>[];
    for (final unit in sortedUnits) {
      final beforePhotos = unit.photosBefore.where((p) => p.isActive).toList();
      final afterPhotos = unit.photosAfter.where((p) => p.isActive).toList();
      if (beforePhotos.isNotEmpty) {
        sectionDefs.add(_SectionDef(
          title: '${unit.name}: Before',
          items: beforePhotos
              .map((p) => _PhotoItem(
                    cloudUrl: p.cloudUrl,
                    storagePath:
                        'jobs/${job.jobId}/${p.relativePath.replaceAll('\\', '/')}',
                    fileName: p.fileName,
                  ))
              .toList(),
        ));
      }
      if (afterPhotos.isNotEmpty) {
        sectionDefs.add(_SectionDef(
          title: '${unit.name}: After',
          items: afterPhotos
              .map((p) => _PhotoItem(
                    cloudUrl: p.cloudUrl,
                    storagePath:
                        'jobs/${job.jobId}/${p.relativePath.replaceAll('\\', '/')}',
                    fileName: p.fileName,
                  ))
              .toList(),
        ));
      }
    }

    final totalPhotos =
        sectionDefs.fold<int>(0, (sum, s) => sum + s.items.length);
    var completed = 0;
    var skipped = 0;

    // Download all photos and build PdfSections.
    final pdfSections = <PdfSection>[];
    for (final def in sectionDefs) {
      final imageBytes = <Uint8List>[];
      for (final item in def.items) {
        onProgress(WebExportProgress(
          total: totalPhotos,
          completed: completed,
          currentFile: item.fileName,
          skipped: skipped,
        ));

        final bytes = await _downloadPhoto(item);
        if (bytes != null) {
          imageBytes.add(bytes);
        } else {
          skipped++;
        }
        completed++;
      }
      if (imageBytes.isNotEmpty) {
        pdfSections.add(PdfSection(title: def.title, imageBytes: imageBytes));
      }
    }

    onProgress(WebExportProgress(
      total: totalPhotos,
      completed: totalPhotos,
      currentFile: 'Building PDF…',
      skipped: skipped,
    ));

    final address = [job.address, job.city]
        .where((s) => s != null && s.isNotEmpty)
        .join(', ');

    final pdfBytes = await PdfExportBuilder.build(
      cover: PdfCoverInfo(
        restaurantName: job.restaurantName,
        address: address.isNotEmpty ? address : null,
        shiftDate: job.shiftStartDate,
      ),
      sections: pdfSections,
    );

    final safeName =
        job.restaurantName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    _triggerDownload(pdfBytes, 'KitchenGuard_${safeName}_$ts.pdf');

    final finalProgress = WebExportProgress(
      total: totalPhotos,
      completed: totalPhotos,
      currentFile: 'Done',
      skipped: skipped,
    );
    onProgress(finalProgress);
    return finalProgress;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Future<Uint8List?> _downloadPhoto(_PhotoItem item) async {
    var url = item.cloudUrl;

    if (url == null) {
      try {
        url = await FirebaseStorage.instance
            .ref(item.storagePath)
            .getDownloadURL();
      } catch (_) {
        return null;
      }
    }

    if (url == null) return null;

    try {
      return await _downloadBytes(url);
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> _downloadBytes(String url) {
    final completer = Completer<Uint8List?>();
    final xhr = web.XMLHttpRequest();
    xhr.open('GET', url);
    xhr.responseType = 'arraybuffer';
    xhr.onload = (web.Event e) {
      if (xhr.status == 200 && xhr.response != null) {
        final buffer = (xhr.response! as JSArrayBuffer).toDart;
        completer.complete(buffer.asUint8List());
      } else {
        completer.complete(null);
      }
    }.toJS;
    xhr.onerror = (web.Event e) {
      completer.complete(null);
    }.toJS;
    xhr.send();
    return completer.future;
  }

  static void _triggerDownload(List<int> bytes, String fileName) {
    final jsArray = Uint8List.fromList(bytes).toJS;
    final blob = web.Blob(
      [jsArray].toJS,
      web.BlobPropertyBag(type: 'application/pdf'),
    );
    final blobUrl = web.URL.createObjectURL(blob);
    final anchor =
        web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = blobUrl;
    anchor.download = fileName;
    anchor.click();
    web.URL.revokeObjectURL(blobUrl);
  }
}

class _SectionDef {
  const _SectionDef({required this.title, required this.items});
  final String title;
  final List<_PhotoItem> items;
}

class _PhotoItem {
  const _PhotoItem({
    required this.cloudUrl,
    required this.storagePath,
    required this.fileName,
  });
  final String? cloudUrl;
  final String storagePath;
  final String fileName;
}
