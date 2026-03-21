import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../domain/models/day_note.dart';
import '../../domain/models/job.dart';
import '../../domain/models/job_note.dart';
import '../../domain/models/photo_record.dart';
import '../../domain/models/video_record.dart';
import '../../application/jobs_service.dart';

class JobDetailController {
  JobDetailController({required this.jobs, required this.jobDir});

  final JobsService jobs;
  final Directory jobDir;
  Job? _job;

  List<JobNote> get activeNotes {
    final notes = _job?.notes ?? const [];
    final active = notes
        .where((note) => note.status == 'active')
        .toList(growable: false);
    // newest first
    active.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return active;
  }

  List<JobNote> get allNotes =>
      List<JobNote>.unmodifiable(_job?.notes ?? const []);

  int get photosBeforeCount {
    final units = _job?.units ?? const [];
    return units.fold(0, (sum, u) => sum + u.visibleBeforeCount);
  }

  int get photosAfterCount {
    final units = _job?.units ?? const [];
    return units.fold(0, (sum, u) => sum + u.visibleAfterCount);
  }

  int get preCleanLayoutCount =>
      _job?.preCleanLayoutPhotos.where((photo) => photo.isActive).length ?? 0;

  int get notesCount => activeNotes.length;

  int get videosExitCount =>
      _job?.videos.exit.where((v) => v.isActive).length ?? 0;

  int get videosOtherCount =>
      _job?.videos.other.where((v) => v.isActive).length ?? 0;

  int get missingPhotosCount {
    final units = _job?.units ?? const [];
    var count = 0;
    for (final unit in units) {
      count += unit.photosBefore
          .where((photo) => photo.isMissing && !photo.isDeleted)
          .length;
      count += unit.photosAfter
          .where((photo) => photo.isMissing && !photo.isDeleted)
          .length;
    }
    return count;
  }

  Future<Job> loadJob() async {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    final job = await jobs.jobStore.readJob(jobJsonFile);
    if (job == null) {
      throw StateError('job.json missing: ${jobDir.path}');
    }
    _job = job;
    return job;
  }

  Future<void> capturePhoto({
    required String unitId,
    required String phase,
    required ImagePicker picker,
  }) async {
    final normalizedPhase = phase.trim().toLowerCase();
    final job = _job ?? await loadJob();
    final unit = job.units.firstWhere(
      (u) => u.unitId == unitId,
      orElse: () => throw StateError('Unit not found'),
    );

    if (unit.type.isEmpty || unit.name.trim().isEmpty) {
      throw ArgumentError('Invalid unit data.');
    }

    final picked = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) {
      return;
    }

    await jobs.persistAndRecordPhoto(
      jobDir: jobDir,
      unitType: unit.type,
      unitName: unit.name,
      unitId: unit.unitId,
      phase: normalizedPhase,
      sourceImageFile: File(picked.path),
    );
    await loadJob();
  }

  Future<void> capturePhotoFromFile({
    required String unitId,
    required String phase,
    required File sourceImageFile,
  }) async {
    final normalizedPhase = phase.trim().toLowerCase();
    final job = _job ?? await loadJob();
    final unit = job.units.firstWhere(
      (u) => u.unitId == unitId,
      orElse: () => throw StateError('Unit not found'),
    );

    if (unit.type.isEmpty || unit.name.trim().isEmpty) {
      throw ArgumentError('Invalid unit data.');
    }

    await jobs.persistAndRecordPhoto(
      jobDir: jobDir,
      unitType: unit.type,
      unitName: unit.name,
      unitId: unitId,
      phase: normalizedPhase,
      sourceImageFile: sourceImageFile,
    );
    await loadJob();
  }

  Future<void> softDeletePhoto({
    required String unitId,
    required String phase,
    required String relativePath,
  }) async {
    await jobs.softDeletePhoto(
      jobDir: jobDir,
      unitId: unitId,
      phase: phase,
      relativePath: relativePath,
    );
    await loadJob();
  }

  Future<void> setUnitCompletion({
    required String unitId,
    required bool isComplete,
  }) async {
    final trimmedUnitId = unitId.trim();
    if (trimmedUnitId.isEmpty) {
      throw ArgumentError.value(unitId, 'unitId', 'Unit id cannot be empty.');
    }

    await jobs.setUnitCompletion(
      jobDir: jobDir,
      unitId: trimmedUnitId,
      isComplete: isComplete,
    );
    await loadJob();
  }

  Future<void> renameUnit({
    required String unitId,
    required String newName,
  }) async {
    final trimmedUnitId = unitId.trim();
    if (trimmedUnitId.isEmpty) {
      throw ArgumentError.value(unitId, 'unitId', 'Unit id cannot be empty.');
    }
    await jobs.renameUnit(
      jobDir: jobDir,
      unitId: trimmedUnitId,
      newName: newName,
    );
    await loadJob();
  }

  Future<void> deleteUnitIfEmpty({required String unitId}) async {
    final trimmedUnitId = unitId.trim();
    if (trimmedUnitId.isEmpty) {
      throw ArgumentError.value(unitId, 'unitId', 'Unit id cannot be empty.');
    }
    await jobs.deleteUnitIfEmpty(jobDir: jobDir, unitId: trimmedUnitId);
    await loadJob();
  }

  Future<void> addNote(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(text, 'text', 'Note text cannot be empty.');
    }

    await jobs.addJobNote(jobDir: jobDir, text: trimmed);
    await loadJob();
  }

  Future<void> softDeleteNote(String noteId) async {
    final trimmed = noteId.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(noteId, 'noteId', 'Note id cannot be empty.');
    }

    await jobs.softDeleteJobNote(jobDir: jobDir, noteId: trimmed);
    await loadJob();
  }

  Future<List<VideoRecord>> loadVideos({required String kind}) async {
    final normalized = kind.trim().toLowerCase();
    if (normalized != 'exit' && normalized != 'other') {
      throw ArgumentError.value(
        kind,
        'kind',
        'Invalid kind. Use "exit" or "other".',
      );
    }

    final job = _job ?? await loadJob();
    final bucket = normalized == 'exit' ? job.videos.exit : job.videos.other;
    return bucket.where((v) => v.isActive).toList(growable: false);
  }

  Future<void> captureVideo({
    required String kind,
    required ImagePicker picker,
  }) async {
    final normalized = kind.trim().toLowerCase();
    final picked = await picker.pickVideo(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) {
      return;
    }

    await jobs.persistAndRecordVideo(
      jobDir: jobDir,
      kind: normalized,
      sourceVideoFile: File(picked.path),
    );
    await loadJob();
  }

  Future<void> softDeleteVideo({
    required String kind,
    required String relativePath,
  }) async {
    await jobs.softDeleteVideo(
      jobDir: jobDir,
      kind: kind,
      relativePath: relativePath,
    );
    await loadJob();
  }

  Future<List<PhotoRecord>> loadPreCleanLayoutPhotos() async {
    final job = _job ?? await loadJob();
    return job.preCleanLayoutPhotos
        .where((photo) => photo.isActive)
        .toList(growable: false);
  }

  Future<void> capturePreCleanLayoutPhoto({required ImagePicker picker}) async {
    final picked = await picker.pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.rear,
    );
    if (picked == null) {
      return;
    }

    await jobs.persistAndRecordPreCleanLayoutPhoto(
      jobDir: jobDir,
      sourceImageFile: File(picked.path),
    );
    await loadJob();
  }

  Future<void> capturePreCleanLayoutPhotoFromFile({
    required File sourceImageFile,
  }) async {
    await jobs.persistAndRecordPreCleanLayoutPhoto(
      jobDir: jobDir,
      sourceImageFile: sourceImageFile,
    );
    await loadJob();
  }

  Future<void> softDeletePreCleanLayoutPhoto({
    required String relativePath,
  }) async {
    await jobs.softDeletePreCleanLayoutPhoto(
      jobDir: jobDir,
      relativePath: relativePath,
    );
    await loadJob();
  }

  File videoFileFromRelativePath(String relativePath) {
    return File(p.join(jobDir.path, relativePath));
  }

  Future<File> exportJob() async {
    final jobName = _job?.restaurantName ?? 'Job';
    return await jobs.exportJobZip(jobDir: jobDir, zipBaseName: jobName);
  }

  /// Returns active [DayNote]s for this job's [Job.scheduledDate].
  /// Returns an empty list if [scheduledDate] is null or unset.
  Future<List<DayNote>> loadShiftNotes() async {
    final job = _job ?? await loadJob();
    final date = job.scheduledDate;
    if (date == null || date.isEmpty) return const [];
    return jobs.loadDayNotes(date);
  }

  /// Sets or clears the scheduled date on this job.
  ///
  /// Pass [date] as YYYY-MM-DD, or null to unschedule.
  /// Updates the cached [_job] and returns the updated [Job].
  Future<Job> setScheduledDate(String? date) async {
    final updated = await jobs.setScheduledDate(jobDir, date);
    _job = updated;
    return updated;
  }
}
