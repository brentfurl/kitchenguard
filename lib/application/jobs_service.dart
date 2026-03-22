import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/models/day_note.dart';
import '../domain/models/job.dart';
import '../domain/models/job_note.dart';
import '../domain/models/manager_job_note.dart';
import '../domain/models/photo_record.dart';
import '../domain/models/unit.dart';
import '../domain/models/video_record.dart';
import '../domain/models/videos.dart';
import '../storage/app_paths.dart';
import '../storage/day_note_store.dart';
import '../storage/image_file_store.dart';
import '../storage/job_store.dart';
import '../storage/video_file_store.dart';
import '../utils/unit_sorter.dart';

/// Creates and updates job folders backed by `job.json`.
class JobsService {
  JobsService({
    required this.paths,
    required this.jobStore,
    required this.imageStore,
    required this.videoStore,
    required this.dayNoteStore,
  });

  final AppPaths paths;
  final JobStore jobStore;
  final ImageFileStore imageStore;
  final VideoFileStore videoStore;
  final DayNoteStore dayNoteStore;
  final Uuid _uuid = const Uuid();

  Future<Directory> createJob({
    required String restaurantName,
    required DateTime shiftStartLocal,
    String? scheduledDate,
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

    final job = Job(
      jobId: _uuid.v4(),
      restaurantName: restaurantName,
      shiftStartDate: _formatDateYyyyMmDd(localDate),
      createdAt: DateTime.now().toUtc().toIso8601String(),
      schemaVersion: 3,
      scheduledDate: scheduledDate,
      units: const [],
      notes: const [],
      preCleanLayoutPhotos: const [],
      videos: const Videos.empty(),
    );

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    await jobStore.writeJob(jobJsonFile, job);

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

  /// Updates the restaurant name and/or scheduled date on a job.
  ///
  /// [restaurantName] and [scheduledDate] are applied only when non-null.
  /// To clear the scheduled date, pass the empty string for [scheduledDate]
  /// (the value is converted to `null` internally).
  Future<Job> updateJobDetails({
    required Directory jobDir,
    String? restaurantName,
    String? scheduledDate,
    bool clearScheduledDate = false,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final newName = restaurantName?.trim();
    if (newName != null && newName.isEmpty) {
      throw ArgumentError.value(
        restaurantName,
        'restaurantName',
        'Restaurant name cannot be empty.',
      );
    }

    final updated = Job(
      jobId: job.jobId,
      restaurantName: newName ?? job.restaurantName,
      shiftStartDate: job.shiftStartDate,
      createdAt: job.createdAt,
      schemaVersion: job.schemaVersion,
      units: job.units,
      notes: job.notes,
      managerNotes: job.managerNotes,
      preCleanLayoutPhotos: job.preCleanLayoutPhotos,
      videos: job.videos,
      scheduledDate: clearScheduledDate
          ? null
          : (scheduledDate ?? job.scheduledDate),
      sortOrder: job.sortOrder,
    );
    return jobStore.writeJob(jobJsonFile, updated);
  }

  Future<void> addUnit({
    required Directory jobDir,
    required String unitName,
    required String unitType, // "hood" | "fan" | "misc"
  }) async {
    final normalizedType = unitType.trim().toLowerCase();
    final category = AppPaths.categoryForUnitType(normalizedType);
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
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('job.json missing: ${jobDir.path}');
    }

    final newNorm = _normalizeUnitName(displayName);
    for (final u in job.units) {
      if (u.type.trim().toLowerCase() != normalizedType) continue;
      if (_normalizeUnitName(u.name) == newNorm) {
        throw StateError('Unit name already exists: $displayName');
      }
    }

    if (job.restaurantName.isEmpty || job.shiftStartDate.isEmpty) {
      throw StateError('Invalid job.json in ${jobDir.path}');
    }
    final shiftStartDate = DateTime.parse(job.shiftStartDate);
    final unitId = _uuid.v4();

    final unitPath = await paths.getUnitPathV2(
      restaurantName: job.restaurantName,
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

    final newUnit = Unit(
      unitId: unitId,
      type: normalizedType,
      name: displayName,
      unitFolderName: unitFolderName,
      isComplete: false,
      photosBefore: const [],
      photosAfter: const [],
    );

    await jobStore.writeJob(
      jobJsonFile,
      job.copyWith(units: [...job.units, newUnit]),
    );
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
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final targetIndex = job.units.indexWhere((u) => u.unitId == unitId);
    if (targetIndex < 0) {
      throw StateError('Unit not found for unitId: $unitId');
    }
    final target = job.units[targetIndex];
    final targetType = target.type.trim().toLowerCase();

    final normalizedNew = _normalizeUnitName(displayName);
    for (final u in job.units) {
      if (u.unitId == unitId) continue;
      if (u.type.trim().toLowerCase() != targetType) continue;
      if (_normalizeUnitName(u.name) == normalizedNew) {
        throw StateError('Unit name already exists: $displayName');
      }
    }

    final updatedUnits = job.units
        .map((u) => u.unitId == unitId ? u.copyWith(name: displayName) : u)
        .toList();

    await jobStore.writeJob(jobJsonFile, job.copyWith(units: updatedUnits));
  }

  Future<void> deleteUnitIfEmpty({
    required Directory jobDir,
    required String unitId,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final target = job.units.cast<Unit?>().firstWhere(
      (u) => u!.unitId == unitId,
      orElse: () => null,
    );
    if (target == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    if (target.visibleBeforeCount > 0 || target.visibleAfterCount > 0) {
      throw StateError(
        'Cannot delete unit with photos. Remove photos before deleting the unit.',
      );
    }

    final updatedUnits = job.units.where((u) => u.unitId != unitId).toList();
    await jobStore.writeJob(jobJsonFile, job.copyWith(units: updatedUnits));
  }

  Future<void> setUnitCompletion({
    required Directory jobDir,
    required String unitId,
    required bool isComplete,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final target = job.units.cast<Unit?>().firstWhere(
      (u) => u!.unitId == unitId,
      orElse: () => null,
    );
    if (target == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    final updatedUnit = Unit(
      unitId: target.unitId,
      type: target.type,
      name: target.name,
      unitFolderName: target.unitFolderName,
      isComplete: isComplete,
      completedAt: isComplete ? DateTime.now().toUtc().toIso8601String() : null,
      photosBefore: target.photosBefore,
      photosAfter: target.photosAfter,
    );

    final updatedUnits = job.units
        .map((u) => u.unitId == unitId ? updatedUnit : u)
        .toList();

    await jobStore.writeJob(jobJsonFile, job.copyWith(units: updatedUnits));
  }

  Future<void> addPhotoRecord({
    required Directory jobDir,
    required String unitId,
    required String phase, // "before" | "after"
    required File finalImageFile,
    String? subPhase,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final target = job.units.cast<Unit?>().firstWhere(
      (u) => u!.unitId == unitId,
      orElse: () => null,
    );
    if (target == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    final relativePath = p
        .relative(finalImageFile.path, from: jobDir.path)
        .replaceAll('\\', '/');

    final photoRecord = PhotoRecord(
      photoId: _uuid.v4(),
      fileName: p.basename(finalImageFile.path),
      relativePath: relativePath,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      status: 'local',
      missingLocal: false,
      recovered: false,
      subPhase: subPhase,
    );

    final normalizedPhase = phase.trim().toLowerCase();
    final Unit updatedUnit;
    if (normalizedPhase == 'before') {
      updatedUnit = target.copyWith(
        photosBefore: [...target.photosBefore, photoRecord],
      );
    } else if (normalizedPhase == 'after') {
      updatedUnit = target.copyWith(
        photosAfter: [...target.photosAfter, photoRecord],
      );
    } else {
      throw ArgumentError.value(
        phase,
        'phase',
        'Invalid phase. Use "before" or "after".',
      );
    }

    final updatedUnits = job.units
        .map((u) => u.unitId == unitId ? updatedUnit : u)
        .toList();

    await jobStore.writeJob(jobJsonFile, job.copyWith(units: updatedUnits));
  }

  Future<void> softDeletePhoto({
    required Directory jobDir,
    required String unitId,
    required String phase, // 'before' | 'after'
    required String relativePath,
  }) async {
    final normalizedPhase = phase.trim().toLowerCase();
    if (normalizedPhase != 'before' && normalizedPhase != 'after') {
      throw ArgumentError.value(
        phase,
        'phase',
        'Invalid phase. Use "before" or "after".',
      );
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final target = job.units.cast<Unit?>().firstWhere(
      (u) => u!.unitId == unitId,
      orElse: () => null,
    );
    if (target == null) {
      throw StateError('Unit not found for unitId: $unitId');
    }

    final photos = normalizedPhase == 'before'
        ? target.photosBefore
        : target.photosAfter;
    final photoIdx = photos.indexWhere((ph) => ph.relativePath == relativePath);
    if (photoIdx < 0) {
      throw StateError('Photo record not found: $relativePath');
    }

    final now = DateTime.now().toIso8601String();
    final updatedPhotos = [...photos];
    updatedPhotos[photoIdx] = photos[photoIdx].copyWith(
      status: 'deleted',
      deletedAt: now,
    );

    final updatedUnit = normalizedPhase == 'before'
        ? target.copyWith(photosBefore: updatedPhotos)
        : target.copyWith(photosAfter: updatedPhotos);

    final updatedUnits = job.units
        .map((u) => u.unitId == unitId ? updatedUnit : u)
        .toList();

    await jobStore.writeJob(jobJsonFile, job.copyWith(units: updatedUnits));
  }

  Future<void> persistAndRecordPhoto({
    required Directory jobDir,
    required String unitType,
    required String unitName,
    required String unitId,
    required String phase,
    required File sourceImageFile,
    String? subPhase,
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
      subPhase: subPhase,
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
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final now = DateTime.now();
    final timestamp = _formatTimestampForFilename(now);

    late final String fileBaseName;
    if (normalizedKind == 'exit') {
      fileBaseName = 'Exit_video_$timestamp';
    } else {
      var maxIndex = 0;
      var activeCount = 0;
      for (final record in job.videos.other) {
        if (record.isActive) {
          activeCount += 1;
        }
        final match = RegExp(r'^Video(\d+)_').firstMatch(record.fileName);
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
    final videoRecord = VideoRecord(
      videoId: _uuid.v4(),
      fileName: p.basename(finalVideoFile.path),
      relativePath: relativePath,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      status: 'local',
    );

    final Videos updatedVideos;
    if (normalizedKind == 'exit') {
      updatedVideos = job.videos.copyWith(
        exit: [...job.videos.exit, videoRecord],
      );
    } else {
      updatedVideos = job.videos.copyWith(
        other: [...job.videos.other, videoRecord],
      );
    }

    await jobStore.writeJob(jobJsonFile, job.copyWith(videos: updatedVideos));
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
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final bucket = normalizedKind == 'exit'
        ? job.videos.exit
        : job.videos.other;
    final idx = bucket.indexWhere((v) => v.relativePath == relativePath);
    if (idx < 0) {
      throw StateError('Video record not found: $relativePath');
    }

    final now = DateTime.now().toIso8601String();
    final updatedBucket = [...bucket];
    updatedBucket[idx] = bucket[idx].copyWith(
      status: 'deleted',
      deletedAt: now,
    );

    final Videos updatedVideos;
    if (normalizedKind == 'exit') {
      updatedVideos = job.videos.copyWith(exit: updatedBucket);
    } else {
      updatedVideos = job.videos.copyWith(other: updatedBucket);
    }

    await jobStore.writeJob(jobJsonFile, job.copyWith(videos: updatedVideos));
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
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final note = JobNote(
      noteId: _uuid.v4(),
      text: noteText,
      createdAt: DateTime.now().toIso8601String(),
      status: 'active',
    );

    await jobStore.writeJob(
      jobJsonFile,
      job.copyWith(notes: [...job.notes, note]),
    );
    return note;
  }

  Future<void> softDeleteJobNote({
    required Directory jobDir,
    required String noteId,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final idx = job.notes.indexWhere((n) => n.noteId == noteId);
    if (idx < 0) {
      throw StateError('Note not found: $noteId');
    }

    final updatedNotes = [...job.notes];
    updatedNotes[idx] = job.notes[idx].copyWith(status: 'deleted');

    await jobStore.writeJob(jobJsonFile, job.copyWith(notes: updatedNotes));
  }

  // ---------------------------------------------------------------------------
  // Manager Job Notes
  // ---------------------------------------------------------------------------

  Future<ManagerJobNote> addManagerNote({
    required Directory jobDir,
    required String text,
  }) async {
    final noteText = text.trim();
    if (noteText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Note text cannot be empty.');
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final note = ManagerJobNote(
      noteId: _uuid.v4(),
      text: noteText,
      createdAt: DateTime.now().toIso8601String(),
      status: 'active',
    );

    await jobStore.writeJob(
      jobJsonFile,
      job.copyWith(managerNotes: [...job.managerNotes, note]),
    );
    return note;
  }

  Future<void> softDeleteManagerNote({
    required Directory jobDir,
    required String noteId,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final idx = job.managerNotes.indexWhere((n) => n.noteId == noteId);
    if (idx < 0) {
      throw StateError('Manager note not found: $noteId');
    }

    final updatedNotes = [...job.managerNotes];
    updatedNotes[idx] = job.managerNotes[idx].copyWith(status: 'deleted');

    await jobStore.writeJob(
      jobJsonFile,
      job.copyWith(managerNotes: updatedNotes),
    );
  }

  Future<void> editManagerNote({
    required Directory jobDir,
    required String noteId,
    required String newText,
  }) async {
    final trimmed = newText.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(
        newText,
        'newText',
        'Note text cannot be empty.',
      );
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final idx = job.managerNotes.indexWhere((n) => n.noteId == noteId);
    if (idx < 0) {
      throw StateError('Manager note not found: $noteId');
    }

    final updatedNotes = [...job.managerNotes];
    updatedNotes[idx] = job.managerNotes[idx].copyWith(text: trimmed);

    await jobStore.writeJob(
      jobJsonFile,
      job.copyWith(managerNotes: updatedNotes),
    );
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
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final relativePath = p
        .relative(finalFile.path, from: jobDir.path)
        .replaceAll('\\', '/');
    final photoRecord = PhotoRecord(
      photoId: _uuid.v4(),
      fileName: p.basename(finalFile.path),
      relativePath: relativePath,
      capturedAt: DateTime.now().toUtc().toIso8601String(),
      status: 'local',
      missingLocal: false,
      recovered: false,
    );

    await jobStore.writeJob(
      jobJsonFile,
      job.copyWith(
        preCleanLayoutPhotos: [...job.preCleanLayoutPhotos, photoRecord],
      ),
    );
  }

  Future<void> softDeletePreCleanLayoutPhoto({
    required Directory jobDir,
    required String relativePath,
  }) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final idx = job.preCleanLayoutPhotos.indexWhere(
      (ph) => ph.relativePath == relativePath,
    );
    if (idx < 0) {
      throw StateError('Pre-clean layout photo not found: $relativePath');
    }

    final now = DateTime.now().toIso8601String();
    final updatedPhotos = [...job.preCleanLayoutPhotos];
    updatedPhotos[idx] = job.preCleanLayoutPhotos[idx].copyWith(
      status: 'deleted',
      deletedAt: now,
    );

    await jobStore.writeJob(
      jobJsonFile,
      job.copyWith(preCleanLayoutPhotos: updatedPhotos),
    );
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
      final exportJob = await _buildSortedExportJob(jobDir);
      final exportJobJson = exportJob?.toJson();
      final sortedUnits = exportJob?.units ?? const <Unit>[];
      final liveUnitPhotoPaths = _collectLiveUnitPhotoPaths(sortedUnits);

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
        if (_isUnitGalleryPhotoPath(relativePath) &&
            !liveUnitPhotoPaths.contains(relativePath)) {
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
        return _compareExportPaths(left, right, sortedUnits);
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

  Future<Job?> _buildSortedExportJob(Directory jobDir) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    if (!await jobJsonFile.exists()) {
      return null;
    }

    try {
      final job = await jobStore.readJob(jobJsonFile);
      if (job == null) return null;
      final sortedUnits = UnitSorter.sort(job.units);
      return job.copyWith(units: sortedUnits);
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

  Set<String> _collectLiveUnitPhotoPaths(List<Unit> units) {
    final livePaths = <String>{};
    for (final unit in units) {
      for (final photo in unit.photosBefore) {
        if (photo.isActive) {
          livePaths.add(photo.relativePath.replaceAll('\\', '/'));
        }
      }
      for (final photo in unit.photosAfter) {
        if (photo.isActive) {
          livePaths.add(photo.relativePath.replaceAll('\\', '/'));
        }
      }
    }
    return livePaths;
  }

  bool _isUnitGalleryPhotoPath(String relativePath) {
    final normalized = relativePath.replaceAll('\\', '/');
    final parts = p.posix.split(normalized);
    if (parts.length < 4) {
      return false;
    }

    final root = parts.first;
    if (root != AppPaths.hoodsCategory &&
        root != AppPaths.fansCategory &&
        root != AppPaths.miscCategory) {
      return false;
    }

    final phaseDir = parts[2].toLowerCase();
    final beforeDir = AppPaths.beforeFolderName.toLowerCase();
    final afterDir = AppPaths.afterFolderName.toLowerCase();
    return phaseDir == beforeDir || phaseDir == afterDir;
  }

  int _compareExportPaths(
    String left,
    String right,
    List<Unit> sortedUnits,
  ) {
    final leftParts = p.posix.split(left);
    final rightParts = p.posix.split(right);
    final leftRoot = leftParts.isEmpty ? '' : leftParts.first;
    final rightRoot = rightParts.isEmpty ? '' : rightParts.first;

    final rootCmp = _exportRootRank(leftRoot).compareTo(
      _exportRootRank(rightRoot),
    );
    if (rootCmp != 0) {
      return rootCmp;
    }

    if (_isUnitCategoryRoot(leftRoot) && _isUnitCategoryRoot(rightRoot)) {
      final unitOrder = _exportUnitFolderOrderMap(sortedUnits);
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

  Map<String, int> _exportUnitFolderOrderMap(List<Unit> sortedUnits) {
    final map = <String, int>{};
    for (var i = 0; i < sortedUnits.length; i++) {
      final unit = sortedUnits[i];
      if (unit.unitFolderName.isNotEmpty) {
        map[unit.unitFolderName] = i;
      }
      if (unit.name.isNotEmpty && unit.unitId.isNotEmpty) {
        map[paths.unitFolderName(unitName: unit.name, unitId: unit.unitId)] = i;
      }
      if (unit.name.isNotEmpty) {
        map[paths.sanitizeName(unit.name)] = i;
      }
    }
    return map;
  }

  Future<String?> _buildExportNotesText(Directory jobDir) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    if (!await jobJsonFile.exists()) {
      return null;
    }

    final Job job;
    try {
      final loaded = await jobStore.readJob(jobJsonFile);
      if (loaded == null) return null;
      job = loaded;
    } on FormatException {
      return null;
    } on FileSystemException {
      return null;
    }

    final activeNotes = job.notes
        .where((n) => n.isActive)
        .map((n) => <String, String>{
              'text': n.text
                  .replaceAll(RegExp(r'[\r\n]+'), ' ')
                  .trim(),
              'createdAt': n.createdAt,
            })
        .where((m) => (m['text'] ?? '').isNotEmpty)
        .toList();

    if (activeNotes.isEmpty) {
      return null;
    }

    activeNotes.sort(
      (a, b) => (a['createdAt'] ?? '').compareTo(b['createdAt'] ?? ''),
    );

    final buffer = StringBuffer();
    buffer.writeln('Notes');
    if (job.restaurantName.isNotEmpty) {
      buffer.writeln('Restaurant: ${job.restaurantName}');
    }
    if (job.shiftStartDate.isNotEmpty) {
      buffer.writeln('Shift: ${job.shiftStartDate}');
    }
    buffer.writeln();
    for (final note in activeNotes) {
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
    final category = AppPaths.categoryForUnitType(unitType.trim().toLowerCase());
    if (category == null) {
      throw ArgumentError.value(
        unitType,
        'unitType',
        'Invalid unit type. Use "hood", "fan", or "misc".',
      );
    }

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final target = job.units.cast<Unit?>().firstWhere(
      (u) => u!.unitId == unitId,
      orElse: () => null,
    );
    if (target == null) {
      throw StateError('Unit not found in job.json: $unitId');
    }

    final effectiveUnitName =
        target.name.isNotEmpty ? target.name : unitName;

    if (target.unitFolderName.isNotEmpty) {
      return target.unitFolderName;
    }

    if (job.restaurantName.isEmpty || job.shiftStartDate.isEmpty) {
      throw StateError('Invalid job.json in ${jobDir.path}');
    }
    final shiftStartDate = DateTime.parse(job.shiftStartDate);

    final unitPathV2 = await paths.getUnitPathV2(
      restaurantName: job.restaurantName,
      shiftStartDate: shiftStartDate,
      categoryName: category,
      unitName: effectiveUnitName,
      unitId: unitId,
    );
    final unitPathLegacy = await paths.getUnitPath(
      restaurantName: job.restaurantName,
      shiftStartDate: shiftStartDate,
      categoryName: category,
      unitName: effectiveUnitName,
    );

    final unitDirV2 = Directory(unitPathV2);
    final unitDirLegacy = Directory(unitPathLegacy);

    final String resolvedFolderName;
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

    final updatedUnit = Unit(
      unitId: target.unitId,
      type: target.type,
      name: target.name,
      unitFolderName: resolvedFolderName,
      isComplete: target.isComplete,
      completedAt: target.completedAt,
      photosBefore: target.photosBefore,
      photosAfter: target.photosAfter,
    );

    final updatedUnits = job.units
        .map((u) => u.unitId == unitId ? updatedUnit : u)
        .toList();

    await jobStore.writeJob(jobJsonFile, job.copyWith(units: updatedUnits));

    return resolvedFolderName;
  }

  // ---------------------------------------------------------------------------
  // Job Completion
  // ---------------------------------------------------------------------------

  /// Marks a job as complete by setting [Job.completedAt] to now (UTC).
  Future<Job> markJobComplete(Directory jobDir) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final updated = Job(
      jobId: job.jobId,
      restaurantName: job.restaurantName,
      shiftStartDate: job.shiftStartDate,
      createdAt: job.createdAt,
      schemaVersion: job.schemaVersion,
      units: job.units,
      notes: job.notes,
      managerNotes: job.managerNotes,
      preCleanLayoutPhotos: job.preCleanLayoutPhotos,
      videos: job.videos,
      scheduledDate: job.scheduledDate,
      sortOrder: job.sortOrder,
      completedAt: DateTime.now().toUtc().toIso8601String(),
    );
    return jobStore.writeJob(jobJsonFile, updated);
  }

  /// Reopens a completed job by clearing [Job.completedAt].
  Future<Job> reopenJob(Directory jobDir) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final updated = Job(
      jobId: job.jobId,
      restaurantName: job.restaurantName,
      shiftStartDate: job.shiftStartDate,
      createdAt: job.createdAt,
      schemaVersion: job.schemaVersion,
      units: job.units,
      notes: job.notes,
      managerNotes: job.managerNotes,
      preCleanLayoutPhotos: job.preCleanLayoutPhotos,
      videos: job.videos,
      scheduledDate: job.scheduledDate,
      sortOrder: job.sortOrder,
      completedAt: null,
    );
    return jobStore.writeJob(jobJsonFile, updated);
  }

  // ---------------------------------------------------------------------------
  // Scheduling
  // ---------------------------------------------------------------------------

  /// Sets (or clears) the scheduled date on a job.
  ///
  /// Pass [scheduledDate] as a YYYY-MM-DD string, or null to unschedule.
  /// Returns the updated [Job] with [Job.updatedAt] stamped to now.
  Future<Job> setScheduledDate(
    Directory jobDir,
    String? scheduledDate,
  ) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    // Construct directly so a null value clears the field (copyWith cannot
    // distinguish "not provided" from "explicitly null" for nullable fields).
    final updated = Job(
      jobId: job.jobId,
      restaurantName: job.restaurantName,
      shiftStartDate: job.shiftStartDate,
      createdAt: job.createdAt,
      schemaVersion: job.schemaVersion,
      units: job.units,
      notes: job.notes,
      managerNotes: job.managerNotes,
      preCleanLayoutPhotos: job.preCleanLayoutPhotos,
      videos: job.videos,
      scheduledDate: scheduledDate,
      sortOrder: job.sortOrder,
    );
    return jobStore.writeJob(jobJsonFile, updated);
  }

  /// Sets (or clears) the sort order on a job within a day card.
  ///
  /// Returns the updated [Job] with [Job.updatedAt] stamped to now.
  Future<Job> setSortOrder(Directory jobDir, int? sortOrder) async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('Missing job.json in ${jobDir.path}');
    }

    final updated = Job(
      jobId: job.jobId,
      restaurantName: job.restaurantName,
      shiftStartDate: job.shiftStartDate,
      createdAt: job.createdAt,
      schemaVersion: job.schemaVersion,
      units: job.units,
      notes: job.notes,
      managerNotes: job.managerNotes,
      preCleanLayoutPhotos: job.preCleanLayoutPhotos,
      videos: job.videos,
      scheduledDate: job.scheduledDate,
      sortOrder: sortOrder,
    );
    return jobStore.writeJob(jobJsonFile, updated);
  }

  // ---------------------------------------------------------------------------
  // Day Notes
  // ---------------------------------------------------------------------------

  /// Creates a new [DayNote] for [date] with [text] and persists it.
  ///
  /// Throws [ArgumentError] if [text] is empty.
  Future<DayNote> addDayNote(String date, String text) async {
    final noteText = text.trim();
    if (noteText.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Note text cannot be empty.');
    }

    final all = await dayNoteStore.readAll();
    final existing = all[date] ?? [];

    final note = DayNote(
      noteId: _uuid.v4(),
      date: date,
      text: noteText,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      status: 'active',
    );

    await dayNoteStore.write({...all, date: [...existing, note]});
    return note;
  }

  /// Marks the [DayNote] identified by [noteId] on [date] as deleted.
  ///
  /// Throws [StateError] if the note is not found.
  Future<void> softDeleteDayNote(String date, String noteId) async {
    final all = await dayNoteStore.readAll();
    final notes = all[date] ?? [];

    final idx = notes.indexWhere((n) => n.noteId == noteId);
    if (idx < 0) {
      throw StateError('Day note not found: $noteId');
    }

    final updatedNotes = [...notes];
    updatedNotes[idx] = notes[idx].copyWith(status: 'deleted');

    await dayNoteStore.write({...all, date: updatedNotes});
  }

  /// Returns only active [DayNote]s for [date].
  Future<List<DayNote>> loadDayNotes(String date) async {
    final notes = await dayNoteStore.readForDate(date);
    return notes.where((n) => n.isActive).toList();
  }

  /// Returns the full unfiltered map of all day notes (all dates, all statuses).
  ///
  /// Used by JobsHome to build day-grouped cards.
  Future<Map<String, List<DayNote>>> loadAllDayNotes() {
    return dayNoteStore.readAll();
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
}
