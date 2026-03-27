import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:web/web.dart' as web;

import '../domain/models/job.dart';

/// Progress state emitted during a web ZIP export.
class WebExportProgress {
  const WebExportProgress({
    required this.total,
    required this.completed,
    required this.currentFile,
    this.skipped = 0,
  });

  final int total;
  final int completed;
  final String currentFile;
  final int skipped;

  double get fraction => total > 0 ? completed / total : 0;
  bool get isDone => completed >= total;
}

/// Builds and downloads a ZIP of a job's synced media from the web console.
///
/// Photos and videos are fetched from their Firebase Storage `cloudUrl`.
/// Items without a `cloudUrl` are skipped (counted in [WebExportProgress.skipped]).
class WebExportService {
  /// Collects all downloadable media, builds a ZIP in memory, and triggers
  /// a browser download.
  static Future<WebExportProgress> exportJobZip({
    required Job job,
    required void Function(WebExportProgress) onProgress,
  }) async {
    final archive = Archive();

    // job.json
    final jobJsonBytes = utf8.encode(
      const JsonEncoder.withIndent('  ').convert(job.toJson()),
    );
    archive.addFile(ArchiveFile('job.json', jobJsonBytes.length, jobJsonBytes));

    // notes.txt (field notes only, matching mobile export)
    final activeNotes = job.notes.where((n) => n.isActive).toList();
    if (activeNotes.isNotEmpty) {
      final buf = StringBuffer();
      for (var i = 0; i < activeNotes.length; i++) {
        buf.writeln('${i + 1}. ${activeNotes[i].text}');
      }
      final notesBytes = utf8.encode(buf.toString());
      archive.addFile(
        ArchiveFile('notes.txt', notesBytes.length, notesBytes),
      );
    }

    // Collect downloadable media (pre-clean excluded per export rules)
    final items = <_MediaItem>[];

    for (final unit in job.units) {
      final cat = _categoryForType(unit.type);
      final folder = unit.unitFolderName;

      for (final p in unit.photosBefore.where((p) => p.isActive)) {
        items.add(_MediaItem(
          cloudUrl: p.cloudUrl,
          storagePath: 'jobs/${job.jobId}/${p.relativePath.replaceAll('\\', '/')}',
          archivePath: '$cat/$folder/Before/${p.fileName}',
        ));
      }
      for (final p in unit.photosAfter.where((p) => p.isActive)) {
        items.add(_MediaItem(
          cloudUrl: p.cloudUrl,
          storagePath: 'jobs/${job.jobId}/${p.relativePath.replaceAll('\\', '/')}',
          archivePath: '$cat/$folder/After/${p.fileName}',
        ));
      }
    }

    for (final v in job.videos.exit.where((v) => v.isActive)) {
      items.add(_MediaItem(
        cloudUrl: v.cloudUrl,
        storagePath: 'jobs/${job.jobId}/${v.relativePath.replaceAll('\\', '/')}',
        archivePath: 'Videos/Exit/${v.fileName}',
      ));
    }
    for (final v in job.videos.other.where((v) => v.isActive)) {
      items.add(_MediaItem(
        cloudUrl: v.cloudUrl,
        storagePath: 'jobs/${job.jobId}/${v.relativePath.replaceAll('\\', '/')}',
        archivePath: 'Videos/Other/${v.fileName}',
      ));
    }

    final total = items.length;
    var completed = 0;
    var skipped = 0;

    for (final item in items) {
      onProgress(WebExportProgress(
        total: total,
        completed: completed,
        currentFile: item.archivePath.split('/').last,
        skipped: skipped,
      ));

      var url = item.cloudUrl;

      // Resolve missing cloudUrl from Firebase Storage directly.
      if (url == null) {
        url = await _resolveStorageUrl(item.storagePath);
      }

      if (url == null) {
        skipped++;
        completed++;
        continue;
      }

      try {
        final bytes = await _downloadBytes(url);
        if (bytes != null) {
          archive.addFile(
            ArchiveFile(item.archivePath, bytes.length, bytes),
          );
        } else {
          skipped++;
        }
      } catch (_) {
        skipped++;
      }
      completed++;
    }

    final finalProgress = WebExportProgress(
      total: total,
      completed: total,
      currentFile: 'Building ZIP…',
      skipped: skipped,
    );
    onProgress(finalProgress);

    final zipBytes = ZipEncoder().encode(archive);
    if (zipBytes == null) throw StateError('ZIP encoding failed');

    final safeName =
        job.restaurantName.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final ts = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    _triggerDownload(zipBytes, 'KitchenGuard_${safeName}_$ts.zip');

    return finalProgress;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  static Future<String?> _resolveStorageUrl(String storagePath) async {
    try {
      return await FirebaseStorage.instance
          .ref(storagePath)
          .getDownloadURL();
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
      web.BlobPropertyBag(type: 'application/zip'),
    );
    final blobUrl = web.URL.createObjectURL(blob);
    final anchor =
        web.document.createElement('a') as web.HTMLAnchorElement;
    anchor.href = blobUrl;
    anchor.download = fileName;
    anchor.click();
    web.URL.revokeObjectURL(blobUrl);
  }

  static String _categoryForType(String type) {
    switch (type) {
      case 'hood':
        return 'Hoods';
      case 'fan':
        return 'Fans';
      default:
        return 'Misc';
    }
  }
}

class _MediaItem {
  const _MediaItem({
    required this.cloudUrl,
    required this.storagePath,
    required this.archivePath,
  });
  final String? cloudUrl;
  final String storagePath;
  final String archivePath;
}
