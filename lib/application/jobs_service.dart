import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'models/job_note.dart';
import '../storage/app_paths.dart';
import '../storage/image_file_store.dart';
import '../storage/job_store.dart';
import '../storage/video_file_store.dart';

/// Creates and updates job folders backed by `job.json`.
class JobsService {
  JobsService({
    required this.paths,
    required this.jobStore,
    required this.imageStore,
    required this.videoStore,
  });

  final AppPaths paths;
  final JobStore jobStore;
  final ImageFileStore imageStore;
  final VideoFileStore videoStore;
  final Uuid _uuid = const Uuid();

  Future<Directory> createJob({
    required String restaurantName,
    required DateTime shiftStartLocal,
  }) async {
    final localDate = shiftStartLocal.toLocal();
    final jobPath = await paths.getJobPath(
      restaurantName: restaurantName,
      shiftStartDate: localDate,
    );
    final jobDir = Directory(jobPath);

    if (await jobDir.exists()) {
      throw StateError('Job folder already exists: ${jobDir.path}');
    }

    await jobDir.create(recursive: true);
    await Directory(
      p.join(jobDir.path, AppPaths.hoodsCategory),
    ).create(recursive: true);
    await Directory(
      p.join(jobDir.path, AppPaths.fansCategory),
    ).create(recursive: true);
    await Directory(
      p.join(jobDir.path, AppPaths.miscCategory),
    ).create(recursive: true);

    final jobJson = <String, dynamic>{
      // TODO: Replace with UUID v4 once a UUID dependency is approved for v1.
      'jobId': _newId('job'),
      'restaurantName': restaurantName,
      'shiftStartDate': _formatDateYyyyMmDd(localDate),
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'units': <Map<String, dynamic>>[],
      'notes': <Map<String, dynamic>>[],
      'preCleanLayoutPhotos': <Map<String, dynamic>>[],
      'videos': <String, dynamic>{
        'exit': <Map<String, dynamic>>[],
        'other': <Map<String, dynamic>>[],
      },
    };

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    await jobStore.writeJobJson(jobJsonFile, jobJson);

    return jobDir;
  }

  Future<void> deleteJob({required Directory jobDir}) async {
    if (!await jobDir.exists()) {
      return;
    }

    final rootPath = p.normalize(await paths.getRootPath());
    final jobPath = p.normalize(jobDir.path);
    final isUnderRoot = p.isWithin(rootPath, jobPath) || jobPath == rootPath;
    if (!isUnderRoot) {
      throw StateError('Refusing to delete path outside jobs root: $jobPath');
    }

    final jobJsonFile = File(p.join(jobPath, 'job.json'));
    if (!await jobJsonFile.exists()) {
      throw StateError('Refusing to delete non-job directory: $jobPath');
    }

    await Directory(jobPath).delete(recursive: true);
  }

  Future<void> addUnit({
    required Directory jobDir,
    required String unitName,
    required String unitType, // "hood" | "fan" | "misc"
  }) async {
    final normalizedType = unitType.trim().toLowerCase();
    final category = _categoryForUnitType(normalizedType);
    if (category == null) {
      throw ArgumentError.value(
        unitType,
        'unitType',
        'Invalid unit type. Use "hood", "fan", or "misc".',
      );
    }

    final displayName = unitName.trim();
    if (displayName.isEmpty) {
      throw ArgumentError.value(
        unitName,
        'unitName',
        'Unit name cannot be empty.',
      );
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('job.json missing: ${jobDir.path}');
    }

    final units = (job['units'] as List?) ?? const [];
    final newNorm = _normalizeUnitName(displayName);
    for (final u in units) {
      if (u is! Map) {
        continue;
      }
      final existingType = (u['type'] ?? '').toString().trim().toLowerCase();
      if (existingType != normalizedType) {
        continue;
      }
      final existingName = (u['name'] ?? '').toString();
      if (_normalizeUnitName(existingName) == newNorm) {
        throw StateError('Unit name already exists: $displayName');
      }
    }

    final restaurantName = (job['restaurantName'] ?? '').toString();
    final shiftStartRaw = (job['shiftStartDate'] ?? '').toString();
    if (restaurantName.isEmpty || shiftStartRaw.isEmpty) {
      throw StateError('Invalid job.json in ${jobDir.path}');
    }
    final shiftStartDate = DateTime.parse(shiftStartRaw);
    final unitId = _newId('unit');

    final unitPath = await paths.getUnitPathV2(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
      categoryName: category,
      unitName: displayName,
      unitId: unitId,
    );
    final unitDir = Directory(unitPath);
    final unitFolderName = p.basename(unitDir.path);
    final beforeDir = Directory(
      p.join(unitDir.path, AppPaths.beforeFolderName),
    );
    final afterDir = Directory(p.join(unitDir.path, AppPaths.afterFolderName));

    if (await unitDir.exists()) {
      throw StateError('Unit already exists: $displayName');
    }

    await beforeDir.create(recursive: true);
    await afterDir.create(recursive: true);

    final unitsForWrite =
        (job['units'] as List?)?.cast<Map<String, dynamic>>() ??
        <Map<String, dynamic>>[];
    unitsForWrite.add(<String, dynamic>{
      // TODO: Replace with UUID v4 once a UUID dependency is approved for v1.
      'unitId': unitId,
      'type': normalizedType,
      'name': displayName,
      'unitFolderName': unitFolderName,
      'isComplete': false,
      'photosBefore': <dynamic>[],
      'photosAfter': <dynamic>[],
    });

    job['units'] = unitsForWrite;
    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<void> renameUnit({
    required Directory jobDir,
    required String unitId,
    required String newName,
  }) async {
    final displayName = newName.trim();
    if (displayName.isEmpty) {
      throw ArgumentError.value(
        newName,
        'newName',
        'Unit name cannot be empty.',
      );
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final unitsRaw = job['units'];
    if (unitsRaw is! List) {
      throw StateError('Invalid units data in ${jobDir.path}');
    }

    Map<String, dynamic>? targetUnit;
    for (var i = 0; i < unitsRaw.length; i++) {
      final entry = unitsRaw[i];
      if (entry is! Map) {
        continue;
      }
      final map = entry is Map<String, dynamic>
          ? entry
          : Map<String, dynamic>.from(entry);
      unitsRaw[i] = map;
      if ((map['unitId'] ?? '').toString() == unitId) {
        targetUnit = map;
        break;
      }
    }

    if (targetUnit == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    final targetType = (targetUnit['type'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final normalizedNew = _normalizeUnitName(displayName);
    for (final entry in unitsRaw) {
      if (entry is! Map) {
        continue;
      }
      final map = entry is Map<String, dynamic>
          ? entry
          : Map<String, dynamic>.from(entry);
      final existingUnitId = (map['unitId'] ?? '').toString();
      if (existingUnitId == unitId) {
        continue;
      }
      final existingType = (map['type'] ?? '').toString().trim().toLowerCase();
      if (existingType != targetType) {
        continue;
      }
      final existingName = (map['name'] ?? '').toString();
      if (_normalizeUnitName(existingName) == normalizedNew) {
        throw StateError('Unit name already exists: $displayName');
      }
    }

    targetUnit['name'] = displayName;
    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<void> deleteUnitIfEmpty({
    required Directory jobDir,
    required String unitId,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final unitsRaw = job['units'];
    if (unitsRaw is! List) {
      throw StateError('Invalid units data in ${jobDir.path}');
    }

    var targetIndex = -1;
    Map<String, dynamic>? targetUnit;
    for (var i = 0; i < unitsRaw.length; i++) {
      final entry = unitsRaw[i];
      if (entry is! Map) {
        continue;
      }
      final map = entry is Map<String, dynamic>
          ? entry
          : Map<String, dynamic>.from(entry);
      unitsRaw[i] = map;
      if ((map['unitId'] ?? '').toString() == unitId) {
        targetIndex = i;
        targetUnit = map;
        break;
      }
    }

    if (targetIndex < 0 || targetUnit == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    final hasBefore = _hasVisiblePhotos(targetUnit['photosBefore']);
    final hasAfter = _hasVisiblePhotos(targetUnit['photosAfter']);
    if (hasBefore || hasAfter) {
      throw StateError(
        'Cannot delete unit with photos. Remove photos before deleting the unit.',
      );
    }

    unitsRaw.removeAt(targetIndex);
    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<void> setUnitCompletion({
    required Directory jobDir,
    required String unitId,
    required bool isComplete,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final unitsRaw = (job['units'] as List?) ?? const [];
    Map<String, dynamic>? targetUnit;
    for (final entry in unitsRaw) {
      if (entry is Map<String, dynamic> && entry['unitId'] == unitId) {
        targetUnit = entry;
        break;
      }
      if (entry is Map && entry['unitId'] == unitId) {
        targetUnit = Map<String, dynamic>.from(entry);
        final index = unitsRaw.indexOf(entry);
        if (index >= 0 && index < unitsRaw.length) {
          unitsRaw[index] = targetUnit;
        }
        break;
      }
    }

    if (targetUnit == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    targetUnit['isComplete'] = isComplete;
    if (isComplete) {
      targetUnit['completedAt'] = DateTime.now().toUtc().toIso8601String();
    } else {
      targetUnit.remove('completedAt');
    }

    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<void> addPhotoRecord({
    required Directory jobDir,
    required String unitId,
    required String phase, // "before" | "after"
    required File finalImageFile,
  }) async {
    final photosKey = _photosKeyForPhase(phase);
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final jobJson = await jobStore.readJobJson(jobJsonFile);
    if (jobJson == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final unitsRaw = (jobJson['units'] as List?) ?? const [];
    Map<String, dynamic>? targetUnit;
    for (final entry in unitsRaw) {
      if (entry is Map<String, dynamic> && entry['unitId'] == unitId) {
        targetUnit = entry;
        break;
      }
      if (entry is Map && entry['unitId'] == unitId) {
        targetUnit = Map<String, dynamic>.from(entry);
        final index = unitsRaw.indexOf(entry);
        if (index >= 0 && index < unitsRaw.length) {
          unitsRaw[index] = targetUnit;
        }
        break;
      }
    }

    if (targetUnit == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    final relativePath = p
        .relative(finalImageFile.path, from: jobDir.path)
        .replaceAll('\\', '/');

    final photoRecord = <String, dynamic>{
      'fileName': p.basename(finalImageFile.path),
      'relativePath': relativePath,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'local',
    };

    final photoListRaw = (targetUnit[photosKey] as List?) ?? <dynamic>[];
    photoListRaw.add(photoRecord);
    targetUnit[photosKey] = photoListRaw;

    await jobStore.writeJobJson(jobJsonFile, jobJson);
  }

  Future<void> softDeletePhoto({
    required Directory jobDir,
    required String unitId,
    required String phase, // 'before' | 'after'
    required String relativePath, // unique key for the photo record
  }) async {
    final photosKey = _photosKeyForPhase(phase);
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final jobJson = await jobStore.readJobJson(jobJsonFile);
    if (jobJson == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final unitsRaw = (jobJson['units'] as List?) ?? const [];
    Map<String, dynamic>? targetUnit;
    for (final entry in unitsRaw) {
      if (entry is Map<String, dynamic> && entry['unitId'] == unitId) {
        targetUnit = entry;
        break;
      }
      if (entry is Map && entry['unitId'] == unitId) {
        targetUnit = Map<String, dynamic>.from(entry);
        final index = unitsRaw.indexOf(entry);
        if (index >= 0 && index < unitsRaw.length) {
          unitsRaw[index] = targetUnit;
        }
        break;
      }
    }

    if (targetUnit == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    final photosRaw = (targetUnit[photosKey] as List?) ?? const [];
    Map<String, dynamic>? targetPhoto;
    for (final photo in photosRaw) {
      if (photo is Map<String, dynamic> &&
          (photo['relativePath'] ?? '').toString() == relativePath) {
        targetPhoto = photo;
        break;
      }
      if (photo is Map &&
          (photo['relativePath'] ?? '').toString() == relativePath) {
        targetPhoto = Map<String, dynamic>.from(photo);
        final index = photosRaw.indexOf(photo);
        if (index >= 0 && index < photosRaw.length) {
          photosRaw[index] = targetPhoto;
        }
        break;
      }
    }

    if (targetPhoto == null) {
      throw StateError('Photo record not found: $relativePath');
    }

    targetPhoto['status'] = 'deleted';
    targetPhoto['deletedAt'] = DateTime.now().toIso8601String();
    targetUnit[photosKey] = photosRaw;

    await jobStore.writeJobJson(jobJsonFile, jobJson);
  }

  Future<void> persistAndRecordPhoto({
    required Directory jobDir,
    required String unitType,
    required String unitName,
    required String unitId,
    required String phase,
    required File sourceImageFile,
  }) async {
    final resolvedUnitFolderName = await _resolveUnitFolderNameForPhoto(
      jobDir: jobDir,
      unitType: unitType,
      unitName: unitName,
      unitId: unitId,
    );

    final finalImageFile = await imageStore.persistPhoto(
      jobDir: jobDir,
      unitType: unitType,
      unitFolderName: resolvedUnitFolderName,
      phase: phase,
      sourceImageFile: sourceImageFile,
    );

    await addPhotoRecord(
      jobDir: jobDir,
      unitId: unitId,
      phase: phase,
      finalImageFile: finalImageFile,
    );
  }

  Future<void> persistAndRecordVideo({
    required Directory jobDir,
    required String kind, // 'exit' | 'other'
    required File sourceVideoFile,
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (normalizedKind != 'exit' && normalizedKind != 'other') {
      throw ArgumentError.value(
        kind,
        'kind',
        'Invalid kind. Use "exit" or "other".',
      );
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final videos = _getVideosBuckets(job);
    final now = DateTime.now();
    final timestamp = _formatTimestampForFilename(now);

    late final String fileBaseName;
    if (normalizedKind == 'exit') {
      fileBaseName = 'Exit_video_$timestamp';
    } else {
      final otherVideos = videos['other'] ?? const <Map<String, dynamic>>[];
      var maxIndex = 0;
      var activeCount = 0;
      for (final record in otherVideos) {
        final status = (record['status'] ?? 'local').toString();
        if (status != 'deleted') {
          activeCount += 1;
        }
        final fileName = (record['fileName'] ?? '').toString();
        final match = RegExp(r'^Video(\d+)_').firstMatch(fileName);
        final parsed = match == null ? null : int.tryParse(match.group(1)!);
        if (parsed != null && parsed > maxIndex) {
          maxIndex = parsed;
        }
      }
      final nextIndex = maxIndex > 0 ? maxIndex + 1 : activeCount + 1;
      fileBaseName = 'Video${nextIndex}_$timestamp';
    }

    final finalVideoFile = await videoStore.persistVideo(
      jobDir: jobDir,
      kind: normalizedKind,
      fileBaseName: fileBaseName,
      sourceVideoFile: sourceVideoFile,
    );

    final relativePath = p
        .relative(finalVideoFile.path, from: jobDir.path)
        .replaceAll('\\', '/');
    final record = <String, dynamic>{
      'fileName': p.basename(finalVideoFile.path),
      'relativePath': relativePath,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'local',
    };

    final bucket = videos[normalizedKind]!;
    bucket.add(record);
    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<void> softDeleteVideo({
    required Directory jobDir,
    required String kind, // 'exit' | 'other'
    required String relativePath,
  }) async {
    final normalizedKind = kind.trim().toLowerCase();
    if (normalizedKind != 'exit' && normalizedKind != 'other') {
      throw ArgumentError.value(
        kind,
        'kind',
        'Invalid kind. Use "exit" or "other".',
      );
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final videos = _getVideosBuckets(job);
    final bucket = videos[normalizedKind]!;
    Map<String, dynamic>? target;
    for (final record in bucket) {
      if ((record['relativePath'] ?? '').toString() == relativePath) {
        target = record;
        break;
      }
    }

    if (target == null) {
      throw StateError('Video record not found: $relativePath');
    }

    target['status'] = 'deleted';
    target['deletedAt'] = DateTime.now().toIso8601String();
    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<JobNote> addJobNote({
    required Directory jobDir,
    required String text,
  }) async {
    final noteText = text.trim();
    if (noteText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Note text cannot be empty.');
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final notes = _getNotes(job);
    final note = JobNote(
      noteId: _uuid.v4(),
      text: noteText,
      createdAt: DateTime.now().toIso8601String(),
      status: 'active',
    );
    notes.add(note.toJson());
    await jobStore.writeJobJson(jobJsonFile, job);
    return note;
  }

  Future<void> softDeleteJobNote({
    required Directory jobDir,
    required String noteId,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final notes = _getNotes(job);
    Map<String, dynamic>? target;
    for (final note in notes) {
      if ((note['noteId'] ?? '').toString() == noteId) {
        target = note;
        break;
      }
    }
    if (target == null) {
      throw StateError('Note not found: $noteId');
    }

    target['status'] = 'deleted';
    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<void> persistAndRecordPreCleanLayoutPhoto({
    required Directory jobDir,
    required File sourceImageFile,
  }) async {
    final precleanDir = Directory(p.join(jobDir.path, 'PreCleanLayout'));
    await precleanDir.create(recursive: true);

    var ext = p.extension(sourceImageFile.path).toLowerCase();
    if (ext.isEmpty) {
      ext = '.jpg';
    }
    final timestamp = _formatTimestampForFilename(DateTime.now());
    final baseName = 'PreCleanLayout_$timestamp';
    var fileName = '$baseName$ext';
    var finalFile = File(p.join(precleanDir.path, fileName));
    var collision = 1;
    while (await finalFile.exists()) {
      fileName = '${baseName}_$collision$ext';
      finalFile = File(p.join(precleanDir.path, fileName));
      collision += 1;
    }

    final tempFile = File(p.join(precleanDir.path, '.tmp_$fileName'));
    await sourceImageFile.copy(tempFile.path);
    if (await finalFile.exists()) {
      await finalFile.delete();
    }
    await tempFile.rename(finalFile.path);

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final records = _getPreCleanLayoutPhotos(job);
    final relativePath = p
        .relative(finalFile.path, from: jobDir.path)
        .replaceAll('\\', '/');
    records.add(<String, dynamic>{
      'fileName': p.basename(finalFile.path),
      'relativePath': relativePath,
      'capturedAt': DateTime.now().toUtc().toIso8601String(),
      'status': 'local',
    });

    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<void> softDeletePreCleanLayoutPhoto({
    required Directory jobDir,
    required String relativePath,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJobJson(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final records = _getPreCleanLayoutPhotos(job);
    Map<String, dynamic>? target;
    for (final record in records) {
      if ((record['relativePath'] ?? '').toString() == relativePath) {
        target = record;
        break;
      }
    }
    if (target == null) {
      throw StateError('Pre-clean layout photo not found: $relativePath');
    }

    target['status'] = 'deleted';
    target['deletedAt'] = DateTime.now().toIso8601String();
    await jobStore.writeJobJson(jobJsonFile, job);
  }

  Future<File> exportJobZip({
    required Directory jobDir,
    required String zipBaseName,
  }) async {
    if (!await jobDir.exists()) {
      throw StateError('Job directory missing: ${jobDir.path}');
    }

    final now = DateTime.now();
    final safeBase = _sanitizeZipBaseName(zipBaseName);
    final timestamp = _formatExportTimestamp(now);
    final exportDir = Directory(
      p.join(Directory.systemTemp.path, 'KitchenGuardExports'),
    );
    await exportDir.create(recursive: true);

    final zipFile = File(
      p.join(exportDir.path, 'KitchenGuard_${safeBase}_$timestamp.zip'),
    );
    final encoder = ZipFileEncoder();
    encoder.create(zipFile.path);
    File? tempNotesFile;
    File? tempExportJobJsonFile;

    try {
      final exportJobJson = await _buildExportJobJson(jobDir);
      if (exportJobJson != null) {
        tempExportJobJsonFile = File(
          p.join(
            exportDir.path,
            '.job_${DateTime.now().microsecondsSinceEpoch}.json',
          ),
        );
        await tempExportJobJsonFile.writeAsString(
          jsonEncode(exportJobJson),
          flush: true,
        );
        encoder.addFile(tempExportJobJsonFile, 'job.json');
      }

      final notesText = await _buildExportNotesText(jobDir);
      if (notesText != null) {
        tempNotesFile = File(
          p.join(
            exportDir.path,
            '.notes_${DateTime.now().microsecondsSinceEpoch}.txt',
          ),
        );
        await tempNotesFile.writeAsString(notesText, flush: true);
        encoder.addFile(tempNotesFile, 'notes.txt');
      }

      final filesForExport = <Map<String, dynamic>>[];
      await for (final entity in jobDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is! File) {
          continue;
        }
        final relativePath = p
            .relative(entity.path, from: jobDir.path)
            .replaceAll('\\', '/');
        if (_isExcludedFromExport(relativePath)) {
          continue;
        }
        if (tempExportJobJsonFile != null && relativePath == 'job.json') {
          continue;
        }
        filesForExport.add(<String, dynamic>{
          'file': entity,
          'relativePath': relativePath,
        });
      }

      filesForExport.sort((a, b) {
        final left = (a['relativePath'] ?? '').toString();
        final right = (b['relativePath'] ?? '').toString();
        return _compareExportPaths(left, right, exportJobJson);
      });

      for (final item in filesForExport) {
        final entity = item['file'] as File;
        final relativePath = (item['relativePath'] ?? '').toString();
        try {
          if (!await entity.exists()) {
            continue;
          }
          encoder.addFile(entity, relativePath);
        } on FileSystemException {
          // Skip files that disappear mid-export.
        }
      }
    } finally {
      encoder.close();
      if (tempNotesFile != null) {
        try {
          if (await tempNotesFile.exists()) {
            await tempNotesFile.delete();
          }
        } on FileSystemException {
          // Best effort cleanup only.
        }
      }
      if (tempExportJobJsonFile != null) {
        try {
          if (await tempExportJobJsonFile.exists()) {
            await tempExportJobJsonFile.delete();
          }
        } on FileSystemException {
          // Best effort cleanup only.
        }
      }
    }

    await _cleanupOlderExportZips(exportDir: exportDir, keepFile: zipFile);
    return zipFile;
  }

  Future<void> _cleanupOlderExportZips({
    required Directory exportDir,
    required File keepFile,
  }) async {
    final keepPath = p.normalize(keepFile.path);
    final candidates = <File>[];

    await for (final entity in exportDir.list(followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final fileName = p.basename(entity.path);
      final isKitchenGuardExport =
          fileName.startsWith('KitchenGuard_') && fileName.endsWith('.zip');
      if (!isKitchenGuardExport) {
        continue;
      }
      if (p.normalize(entity.path) == keepPath) {
        continue;
      }
      candidates.add(entity);
    }

    for (final file in candidates) {
      try {
        if (await file.exists()) {
          await file.delete();
        }
      } on FileSystemException {
        // Best effort cleanup only.
      }
    }
  }

  Future<Map<String, dynamic>?> _buildExportJobJson(Directory jobDir) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    if (!await jobJsonFile.exists()) {
      return null;
    }

    try {
      final raw = await jobJsonFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      final job = decoded is Map<String, dynamic>
          ? Map<String, dynamic>.from(decoded)
          : Map<String, dynamic>.from(decoded);
      final orderedUnits = _getWorkflowOrderedUnits(job['units']);
      job['units'] = orderedUnits;
      return job;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }
  }

  bool _isExcludedFromExport(String relativePath) {
    return relativePath == 'PreCleanLayout' ||
        relativePath.startsWith('PreCleanLayout/');
  }

  int _compareExportPaths(
    String left,
    String right,
    Map<String, dynamic>? exportJobJson,
  ) {
    final leftParts = p.posix.split(left);
    final rightParts = p.posix.split(right);
    final leftRoot = leftParts.isEmpty ? '' : leftParts.first;
    final rightRoot = rightParts.isEmpty ? '' : rightParts.first;

    final rootCmp = _exportRootRank(
      leftRoot,
    ).compareTo(_exportRootRank(rightRoot));
    if (rootCmp != 0) {
      return rootCmp;
    }

    if (_isUnitCategoryRoot(leftRoot) && _isUnitCategoryRoot(rightRoot)) {
      final unitOrder = _exportUnitFolderOrderMap(exportJobJson);
      final leftUnitFolder = leftParts.length > 1 ? leftParts[1] : '';
      final rightUnitFolder = rightParts.length > 1 ? rightParts[1] : '';
      final leftUnitRank = unitOrder[leftUnitFolder] ?? 1 << 20;
      final rightUnitRank = unitOrder[rightUnitFolder] ?? 1 << 20;
      final unitCmp = leftUnitRank.compareTo(rightUnitRank);
      if (unitCmp != 0) {
        return unitCmp;
      }
    }

    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  int _exportRootRank(String root) {
    switch (root) {
      case AppPaths.hoodsCategory:
        return 0;
      case AppPaths.fansCategory:
        return 1;
      case AppPaths.miscCategory:
        return 2;
      case 'Videos':
        return 3;
      case 'job.json':
        return 4;
      case 'notes.txt':
        return 5;
      default:
        return 6;
    }
  }

  bool _isUnitCategoryRoot(String root) {
    return root == AppPaths.hoodsCategory ||
        root == AppPaths.fansCategory ||
        root == AppPaths.miscCategory;
  }

  Map<String, int> _exportUnitFolderOrderMap(
    Map<String, dynamic>? exportJobJson,
  ) {
    final map = <String, int>{};
    if (exportJobJson == null) {
      return map;
    }
    final orderedUnits = _getWorkflowOrderedUnits(exportJobJson['units']);
    for (var i = 0; i < orderedUnits.length; i++) {
      final unit = orderedUnits[i];
      final unitName = (unit['name'] ?? '').toString();
      final unitId = (unit['unitId'] ?? '').toString();
      final storedFolder = (unit['unitFolderName'] ?? '').toString().trim();
      if (storedFolder.isNotEmpty) {
        map[storedFolder] = i;
      }
      if (unitName.isNotEmpty && unitId.isNotEmpty) {
        map[paths.unitFolderName(unitName: unitName, unitId: unitId)] = i;
      }
      if (unitName.isNotEmpty) {
        map[paths.sanitizeName(unitName)] = i;
      }
    }
    return map;
  }

  List<Map<String, dynamic>> _getWorkflowOrderedUnits(dynamic rawUnits) {
    if (rawUnits is! List) {
      return const <Map<String, dynamic>>[];
    }

    final units = <Map<String, dynamic>>[];
    for (final item in rawUnits) {
      if (item is Map<String, dynamic>) {
        units.add(Map<String, dynamic>.from(item));
      } else if (item is Map) {
        units.add(Map<String, dynamic>.from(item));
      }
    }

    units.sort((a, b) {
      final typeCmp = _unitTypeRankForExport(
        (a['type'] ?? '').toString(),
      ).compareTo(_unitTypeRankForExport((b['type'] ?? '').toString()));
      if (typeCmp != 0) {
        return typeCmp;
      }

      final aName = _normalizeUnitSortName((a['name'] ?? '').toString());
      final bName = _normalizeUnitSortName((b['name'] ?? '').toString());
      final aNumber = _extractFirstNumber(aName);
      final bNumber = _extractFirstNumber(bName);

      if (aNumber != null && bNumber != null) {
        final numCmp = aNumber.compareTo(bNumber);
        if (numCmp != 0) {
          return numCmp;
        }
      } else if (aNumber != null) {
        return -1;
      } else if (bNumber != null) {
        return 1;
      }

      final nameCmp = aName.compareTo(bName);
      if (nameCmp != 0) {
        return nameCmp;
      }

      final aId = (a['unitId'] ?? '').toString();
      final bId = (b['unitId'] ?? '').toString();
      return aId.compareTo(bId);
    });

    return units;
  }

  int _unitTypeRankForExport(String rawType) {
    switch (rawType.trim().toLowerCase()) {
      case 'hood':
        return 0;
      case 'fan':
        return 1;
      default:
        return 2;
    }
  }

  String _normalizeUnitSortName(String name) {
    final compact = name.trim().toLowerCase();
    return compact
        .replaceAll(RegExp(r'[^a-z0-9]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  int? _extractFirstNumber(String value) {
    final match = RegExp(r'(\d+)').firstMatch(value);
    if (match == null) {
      return null;
    }
    return int.tryParse(match.group(1)!);
  }

  Future<String?> _buildExportNotesText(Directory jobDir) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    if (!await jobJsonFile.exists()) {
      return null;
    }

    Map<String, dynamic> jobJson;
    try {
      final raw = await jobJsonFile.readAsString();
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        return null;
      }
      jobJson = decoded is Map<String, dynamic>
          ? decoded
          : Map<String, dynamic>.from(decoded);
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }

    final notesRaw = jobJson['notes'];
    if (notesRaw is! List) {
      return null;
    }

    final notes = <Map<String, String>>[];
    for (final item in notesRaw) {
      if (item is! Map) {
        continue;
      }
      final map = item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item);
      final status = (map['status'] ?? 'active').toString();
      if (status == 'deleted') {
        continue;
      }
      final text = (map['text'] ?? '')
          .toString()
          .replaceAll(RegExp(r'[\r\n]+'), ' ')
          .trim();
      if (text.isEmpty) {
        continue;
      }
      final createdAt = (map['createdAt'] ?? '').toString();
      notes.add(<String, String>{'text': text, 'createdAt': createdAt});
    }

    if (notes.isEmpty) {
      return null;
    }

    notes.sort(
      (a, b) => (a['createdAt'] ?? '').compareTo(b['createdAt'] ?? ''),
    );

    final restaurantName = (jobJson['restaurantName'] ?? '').toString().trim();
    final shiftStartDate = (jobJson['shiftStartDate'] ?? '').toString().trim();

    final buffer = StringBuffer();
    buffer.writeln('Notes');
    if (restaurantName.isNotEmpty) {
      buffer.writeln('Restaurant: $restaurantName');
    }
    if (shiftStartDate.isNotEmpty) {
      buffer.writeln('Shift: $shiftStartDate');
    }
    buffer.writeln();
    for (final note in notes) {
      buffer.writeln('- ${note['text'] ?? ''}');
    }
    return buffer.toString();
  }

  Future<String> _resolveUnitFolderNameForPhoto({
    required Directory jobDir,
    required String unitType,
    required String unitName,
    required String unitId,
  }) async {
    final category = _categoryForUnitType(unitType.trim().toLowerCase());
    if (category == null) {
      throw ArgumentError.value(
        unitType,
        'unitType',
        'Invalid unit type. Use "hood", "fan", or "misc".',
      );
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final jobJson = await jobStore.readJobJson(jobJsonFile);
    if (jobJson == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final unitsRaw = (jobJson['units'] as List?) ?? const [];
    Map<String, dynamic>? targetUnit;
    for (final entry in unitsRaw) {
      if (entry is Map<String, dynamic> && entry['unitId'] == unitId) {
        targetUnit = entry;
        break;
      }
      if (entry is Map && entry['unitId'] == unitId) {
        targetUnit = Map<String, dynamic>.from(entry);
        final index = unitsRaw.indexOf(entry);
        if (index >= 0 && index < unitsRaw.length) {
          unitsRaw[index] = targetUnit;
        }
        break;
      }
    }

    if (targetUnit == null) {
      throw StateError('Unit not found in job.json: $unitId');
    }

    final effectiveUnitName = (targetUnit['name'] ?? unitName).toString();

    final storedFolderName = (targetUnit['unitFolderName'] ?? '')
        .toString()
        .trim();
    if (storedFolderName.isNotEmpty) {
      return storedFolderName;
    }

    final restaurantName = (jobJson['restaurantName'] ?? '').toString();
    final shiftStartRaw = (jobJson['shiftStartDate'] ?? '').toString();
    if (restaurantName.isEmpty || shiftStartRaw.isEmpty) {
      throw StateError('Invalid job.json in ${jobDir.path}');
    }
    final shiftStartDate = DateTime.parse(shiftStartRaw);

    final unitPathV2 = await paths.getUnitPathV2(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
      categoryName: category,
      unitName: effectiveUnitName,
      unitId: unitId,
    );
    final unitPathLegacy = await paths.getUnitPath(
      restaurantName: restaurantName,
      shiftStartDate: shiftStartDate,
      categoryName: category,
      unitName: effectiveUnitName,
    );

    final unitDirV2 = Directory(unitPathV2);
    final unitDirLegacy = Directory(unitPathLegacy);

    String resolvedFolderName;
    if (await unitDirV2.exists()) {
      resolvedFolderName = p.basename(unitDirV2.path);
    } else if (await unitDirLegacy.exists()) {
      resolvedFolderName = p.basename(unitDirLegacy.path);
    } else {
      await Directory(
        p.join(unitDirV2.path, AppPaths.beforeFolderName),
      ).create(recursive: true);
      await Directory(
        p.join(unitDirV2.path, AppPaths.afterFolderName),
      ).create(recursive: true);
      resolvedFolderName = p.basename(unitDirV2.path);
    }

    targetUnit['unitFolderName'] = resolvedFolderName;
    await jobStore.writeJobJson(jobJsonFile, jobJson);

    return resolvedFolderName;
  }

  Map<String, List<Map<String, dynamic>>> _getVideosBuckets(
    Map<String, dynamic> job,
  ) {
    final videosRaw = job['videos'];
    Map<String, dynamic> videos;
    if (videosRaw is Map<String, dynamic>) {
      videos = videosRaw;
    } else if (videosRaw is Map) {
      videos = Map<String, dynamic>.from(videosRaw);
      job['videos'] = videos;
    } else {
      videos = <String, dynamic>{};
      job['videos'] = videos;
    }

    List<Map<String, dynamic>> normalizeBucket(String key) {
      final raw = videos[key];
      if (raw is List<Map<String, dynamic>>) {
        return raw;
      }
      if (raw is List) {
        final normalized = <Map<String, dynamic>>[];
        for (final item in raw) {
          if (item is Map<String, dynamic>) {
            normalized.add(item);
          } else if (item is Map) {
            normalized.add(Map<String, dynamic>.from(item));
          }
        }
        videos[key] = normalized;
        return normalized;
      }
      final created = <Map<String, dynamic>>[];
      videos[key] = created;
      return created;
    }

    final exit = normalizeBucket('exit');
    final other = normalizeBucket('other');
    return <String, List<Map<String, dynamic>>>{'exit': exit, 'other': other};
  }

  List<Map<String, dynamic>> _getNotes(Map<String, dynamic> job) {
    final raw = job['notes'];
    if (raw is List<Map<String, dynamic>>) {
      return raw;
    }
    if (raw is List) {
      final normalized = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          normalized.add(item);
        } else if (item is Map) {
          normalized.add(Map<String, dynamic>.from(item));
        }
      }
      job['notes'] = normalized;
      return normalized;
    }
    final created = <Map<String, dynamic>>[];
    job['notes'] = created;
    return created;
  }

  List<Map<String, dynamic>> _getPreCleanLayoutPhotos(
    Map<String, dynamic> job,
  ) {
    final raw = job['preCleanLayoutPhotos'];
    if (raw is List<Map<String, dynamic>>) {
      return raw;
    }
    if (raw is List) {
      final normalized = <Map<String, dynamic>>[];
      for (final item in raw) {
        if (item is Map<String, dynamic>) {
          normalized.add(item);
        } else if (item is Map) {
          normalized.add(Map<String, dynamic>.from(item));
        }
      }
      job['preCleanLayoutPhotos'] = normalized;
      return normalized;
    }
    final created = <Map<String, dynamic>>[];
    job['preCleanLayoutPhotos'] = created;
    return created;
  }

  String? _categoryForUnitType(String unitType) {
    switch (unitType) {
      case 'hood':
        return AppPaths.hoodsCategory;
      case 'fan':
        return AppPaths.fansCategory;
      case 'misc':
        return AppPaths.miscCategory;
      default:
        return null;
    }
  }

  String _formatDateYyyyMmDd(DateTime date) {
    final year = date.year.toString().padLeft(4, '0');
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$year-$month-$day';
  }

  String _formatTimestampForFilename(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$y-$m-${d}_$hh-$mm-$ss';
  }

  String _formatExportTimestamp(DateTime now) {
    final y = now.year.toString().padLeft(4, '0');
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    final ss = now.second.toString().padLeft(2, '0');
    return '$y$m${d}_$hh$mm$ss';
  }

  String _sanitizeZipBaseName(String input) {
    final trimmed = input.trim();
    final spacesToUnderscore = trimmed.replaceAll(RegExp(r'\s+'), '_');
    final nonAlnumToUnderscore = spacesToUnderscore.replaceAll(
      RegExp(r'[^a-zA-Z0-9_]'),
      '_',
    );
    final collapsed = nonAlnumToUnderscore
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_+|_+$'), '');
    return collapsed.isEmpty ? 'Job' : collapsed;
  }

  String _normalizeUnitName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _newId(String prefix) {
    final micros = DateTime.now().toUtc().microsecondsSinceEpoch;
    return '$prefix-$micros';
  }

  String _photosKeyForPhase(String phase) {
    switch (phase.trim().toLowerCase()) {
      case 'before':
        return 'photosBefore';
      case 'after':
        return 'photosAfter';
      default:
        throw ArgumentError.value(
          phase,
          'phase',
          'Invalid phase. Use "before" or "after".',
        );
    }
  }

  bool _hasVisiblePhotos(dynamic list) {
    if (list is! List) {
      return false;
    }
    for (final item in list) {
      if (item is! Map) {
        continue;
      }
      final status = (item['status'] ?? 'local').toString();
      final missingLocal = item['missingLocal'] == true;
      if (status != 'deleted' && status != 'missing_local' && !missingLocal) {
        return true;
      }
    }
    return false;
  }
}
