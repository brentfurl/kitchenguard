import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';

class ImageFileStore {
  ImageFileStore({required this.paths});

  final AppPaths paths;

  Future<File> persistPhoto({
    required Directory jobDir,
    required String unitType, // hood|fan|misc
    required String unitFolderName, // sanitized folder name used on disk
    required String phase, // before|after
    required File sourceImageFile,
  }) async {
    final category = _categoryForUnitType(unitType);
    final phaseFolder = _phaseFolderName(phase);

    final destinationDir = Directory(
      p.join(jobDir.path, category, unitFolderName, phaseFolder),
    );
    if (!await destinationDir.exists()) {
      await destinationDir.create(recursive: true);
    }

    final now = DateTime.now().toLocal();
    final phaseName = phaseFolder; // "Before" or "After"
    final fileName =
        '${unitFolderName}_${phaseName}_${_formatTimestamp(now)}.jpg';
    final finalFile = File(p.join(destinationDir.path, fileName));
    final tempFile = File(p.join(destinationDir.path, '.tmp_$fileName'));

    if (!await sourceImageFile.exists()) {
      throw StateError(
        'Source image file does not exist: ${sourceImageFile.path}',
      );
    }

    if (await tempFile.exists()) {
      await tempFile.delete();
    }

    await sourceImageFile.copy(tempFile.path);
    await tempFile.rename(finalFile.path);

    return finalFile;
  }

  String _categoryForUnitType(String unitType) {
    switch (unitType.trim().toLowerCase()) {
      case 'hood':
        return AppPaths.hoodsCategory;
      case 'fan':
        return AppPaths.fansCategory;
      case 'misc':
        return AppPaths.miscCategory;
      default:
        throw ArgumentError.value(
          unitType,
          'unitType',
          'Invalid unit type. Use "hood", "fan", or "misc".',
        );
    }
  }

  String _phaseFolderName(String phase) {
    switch (phase.trim().toLowerCase()) {
      case 'before':
        return AppPaths.beforeFolderName;
      case 'after':
        return AppPaths.afterFolderName;
      default:
        throw ArgumentError.value(
          phase,
          'phase',
          'Invalid phase. Use "before" or "after".',
        );
    }
  }

  String _formatTimestamp(DateTime dateTime) {
    final y = dateTime.year.toString().padLeft(4, '0');
    final m = dateTime.month.toString().padLeft(2, '0');
    final d = dateTime.day.toString().padLeft(2, '0');
    final hh = dateTime.hour.toString().padLeft(2, '0');
    final mm = dateTime.minute.toString().padLeft(2, '0');
    final ss = dateTime.second.toString().padLeft(2, '0');
    return '$y-$m-${d}_$hh-$mm-$ss';
  }
}
