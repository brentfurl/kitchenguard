import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';

typedef AtomicWrite = Future<void> Function(File target, List<int> bytes);

class VideoFileStore {
  VideoFileStore({required this.paths, required this.atomicWrite});

  final AppPaths paths;
  final AtomicWrite atomicWrite;

  Future<File> persistVideo({
    required Directory jobDir,
    required String kind, // 'exit' | 'other'
    required String fileBaseName,
    required File sourceVideoFile,
  }) async {
    if (!await sourceVideoFile.exists()) {
      throw StateError(
        'Source video file does not exist: ${sourceVideoFile.path}',
      );
    }

    final normalizedKind = kind.trim().toLowerCase();
    final destinationDir = switch (normalizedKind) {
      'exit' => Directory(p.join(jobDir.path, 'Videos', 'Exit')),
      'other' => Directory(p.join(jobDir.path, 'Videos', 'Other')),
      _ => throw ArgumentError.value(
        kind,
        'kind',
        'Invalid kind. Use "exit" or "other".',
      ),
    };

    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }

    final ext = p.extension(sourceVideoFile.path).trim().isEmpty
        ? '.mp4'
        : p.extension(sourceVideoFile.path);
    final finalName = '$fileBaseName$ext';
    final finalFile = File(p.join(destinationDir.path, finalName));
    final tempFile = File(p.join(destinationDir.path, '.tmp_$finalName'));

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    // Preferred flow: copy source to temp in destination, then rename to final.
    try {
      await sourceVideoFile.copy(tempFile.path);
    } catch (_) {
      // Fallback: write bytes via injected atomic writer.
      final bytes = await sourceVideoFile.readAsBytes();
      await atomicWrite(tempFile, bytes);
    }

    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalFile.path);

    try {
      await sourceVideoFile.delete();
    } catch (_) {
      // Source cleanup is best-effort.
    }

    return finalFile;
  }
}
