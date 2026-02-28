import 'dart:io';

import 'package:archive/archive.dart';
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
      'videos': <String, dynamic>{
        'exit': <Map<String, dynamic>>[],
        'other': <Map<String, dynamic>>[],
      },
    };

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    await jobStore.writeJobJson(jobJsonFile, jobJson);

    return jobDir;
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
      'photosBefore': <dynamic>[],
      'photosAfter': <dynamic>[],
    });

    job['units'] = unitsForWrite;
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

  Future<File> exportJobZip({
    required Directory jobDir,
    required String zipBaseName,
  }) async {
    if (!await jobDir.exists()) {
      throw StateError('Job directory missing: ${jobDir.path}');
    }

    final now = DateTime.now();
    final safeBase = paths.sanitizeName(zipBaseName).trim();
    final baseName = safeBase.isEmpty ? 'KitchenGuard_Job' : safeBase;
    final timestamp = _formatExportTimestamp(now);
    final exportDir = Directory(
      p.join(Directory.systemTemp.path, 'KitchenGuardExports'),
    );
    await exportDir.create(recursive: true);

    final zipFile = File(p.join(exportDir.path, '${baseName}_$timestamp.zip'));
    final archive = Archive();

    await for (final entity in jobDir.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! File) {
        continue;
      }

      try {
        if (!await entity.exists()) {
          continue;
        }
        final bytes = await entity.readAsBytes();
        final relativePath = p
            .relative(entity.path, from: jobDir.path)
            .replaceAll('\\', '/');
        archive.addFile(ArchiveFile(relativePath, bytes.length, bytes));
      } on FileSystemException {
        // Skip files that disappear mid-export.
      }
    }

    final zipBytes = ZipEncoder().encode(archive);
    await zipFile.writeAsBytes(zipBytes, flush: true);
    return zipFile;
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
}
