import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;

import '../../application/models/job_note.dart';
import '../../application/jobs_service.dart';

class JobDetailController {
  JobDetailController({required this.jobs, required this.jobDir});

  final JobsService jobs;
  final Directory jobDir;
  Map<String, dynamic>? _jobData;
  List<JobNote> _notes = const [];

  List<JobNote> get activeNotes =>
      _notes.where((note) => note.status == 'active').toList(growable: false);
  List<JobNote> get allNotes => List<JobNote>.unmodifiable(_notes);

  int get photosBeforeCount => _countPhotosForPhase('before');
  int get photosAfterCount => _countPhotosForPhase('after');
  int get preCleanLayoutCount =>
      countDisplayablePhotos(_jobData?['preCleanLayoutPhotos']);
  int get videosExitCount => _countVideosForKind('exit');
  int get videosOtherCount => _countVideosForKind('other');
  int get missingPhotosCount => _countMissingPhotos();

  Future<Map<String, dynamic>> loadJob() async {
    final jobJson = File(p.join(jobDir.path, 'job.json'));
    final data = await jobs.jobStore.readJobJson(jobJson);
    if (data == null) {
      throw StateError('job.json missing: ${jobDir.path}');
    }
    _jobData = data;
    _notes = _parseNotes(data);
    return data;
  }

  Map<String, dynamic>? findUnitById(Map<String, dynamic> job, String unitId) {
    final units = (job['units'] as List?) ?? const [];
    for (final unit in units) {
      if (unit is! Map) {
        continue;
      }
      if ((unit['unitId'] ?? '').toString() == unitId) {
        return unit is Map<String, dynamic>
            ? unit
            : Map<String, dynamic>.from(unit);
      }
    }
    return null;
  }

  List<Map<String, dynamic>> bucketPhotos(
    Map<String, dynamic> unit,
    String phase, {
    bool includeDeleted = false,
  }) {
    final normalized = phase.trim().toLowerCase();
    final key = switch (normalized) {
      'before' => 'photosBefore',
      'after' => 'photosAfter',
      _ => throw ArgumentError.value(
        phase,
        'phase',
        'Invalid phase. Use "before" or "after".',
      ),
    };

    final source = unit[key];
    if (source is! List) {
      return const [];
    }

    final result = <Map<String, dynamic>>[];
    for (final item in source) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      if (!includeDeleted && !_isDisplayablePhoto(map)) {
        continue;
      }
      result.add(map);
    }
    return result;
  }

  int countDisplayablePhotos(dynamic source) {
    if (source is! List) {
      return 0;
    }

    var count = 0;
    for (final item in source) {
      if (item is! Map) {
        continue;
      }
      final map = item is Map<String, dynamic>
          ? item
          : Map<String, dynamic>.from(item);
      if (_isDisplayablePhoto(map)) {
        count += 1;
      }
    }
    return count;
  }

  Future<void> capturePhoto({
    required Map<String, dynamic> unit,
    required String phase,
    required ImagePicker picker,
  }) async {
    final normalizedPhase = phase.trim().toLowerCase();
    final unitId = (unit['unitId'] ?? '').toString();
    final unitType = (unit['type'] ?? '').toString();
    final unitName = (unit['name'] ?? '').toString();
    if (unitId.isEmpty || unitType.isEmpty || unitName.trim().isEmpty) {
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
      unitType: unitType,
      unitName: unitName,
      unitId: unitId,
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
    final job = _jobData ?? await loadJob();
    final unit = findUnitById(job, unitId);
    if (unit == null) {
      throw StateError('Unit not found');
    }

    final unitType = (unit['type'] ?? '').toString();
    final unitName = (unit['name'] ?? '').toString();
    if (unitType.isEmpty || unitName.trim().isEmpty) {
      throw ArgumentError('Invalid unit data.');
    }

    await jobs.persistAndRecordPhoto(
      jobDir: jobDir,
      unitType: unitType,
      unitName: unitName,
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

  Future<List<Map<String, dynamic>>> loadVideos({required String kind}) async {
    final normalized = kind.trim().toLowerCase();
    if (normalized != 'exit' && normalized != 'other') {
      throw ArgumentError.value(
        kind,
        'kind',
        'Invalid kind. Use "exit" or "other".',
      );
    }

    final job = _jobData ?? await loadJob();
    final videos = job['videos'];
    if (videos is! Map) {
      return const [];
    }

    final bucket = videos[normalized];
    if (bucket is! List) {
      return const [];
    }

    final result = <Map<String, dynamic>>[];
    for (final item in bucket) {
      if (item is! Map) {
        continue;
      }
      final map = Map<String, dynamic>.from(item);
      final status = (map['status'] ?? 'local').toString();
      if (status == 'deleted') {
        continue;
      }
      result.add(map);
    }
    return result;
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

  Future<List<Map<String, dynamic>>> loadPreCleanLayoutPhotos() async {
    final job = _jobData ?? await loadJob();
    final raw = job['preCleanLayoutPhotos'];
    if (raw is! List) {
      return const [];
    }

    final result = <Map<String, dynamic>>[];
    for (final item in raw) {
      if (item is! Map) {
        continue;
      }
      final map = item is Map<String, dynamic>
          ? Map<String, dynamic>.from(item)
          : Map<String, dynamic>.from(item);
      if (_isDisplayablePhoto(map)) {
        result.add(map);
      }
    }
    return result;
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
    final jobName = (_jobData?['restaurantName'] ?? 'Job').toString();
    return await jobs.exportJobZip(jobDir: jobDir, zipBaseName: jobName);
  }

  List<JobNote> _parseNotes(Map<String, dynamic> job) {
    final raw = job['notes'];
    if (raw is! List) {
      return const [];
    }

    final parsed = <JobNote>[];
    for (final item in raw) {
      if (item is Map<String, dynamic>) {
        parsed.add(JobNote.fromJson(item));
      } else if (item is Map) {
        parsed.add(JobNote.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    parsed.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return parsed;
  }

  List<Map<String, dynamic>> _unitsFromState() {
    final source = _jobData?['units'];
    if (source is! List) {
      return const [];
    }

    final units = <Map<String, dynamic>>[];
    for (final entry in source) {
      if (entry is Map<String, dynamic>) {
        units.add(entry);
      } else if (entry is Map) {
        units.add(Map<String, dynamic>.from(entry));
      }
    }
    return units;
  }

  int _countPhotosForPhase(String phase) {
    final key = phase == 'before' ? 'photosBefore' : 'photosAfter';
    var count = 0;
    for (final unit in _unitsFromState()) {
      count += countDisplayablePhotos(unit[key]);
    }
    return count;
  }

  int _countVideosForKind(String kind) {
    final videos = _jobData?['videos'];
    if (videos is! Map) {
      return 0;
    }
    final bucket = videos[kind];
    if (bucket is! List) {
      return 0;
    }

    var count = 0;
    for (final item in bucket) {
      if (item is! Map) {
        continue;
      }
      final status = (item['status'] ?? 'local').toString();
      if (status == 'deleted') {
        continue;
      }
      count += 1;
    }
    return count;
  }

  int _countMissingPhotos() {
    var count = 0;
    for (final unit in _unitsFromState()) {
      count += _countMissingInList(unit['photosBefore']);
      count += _countMissingInList(unit['photosAfter']);
    }
    return count;
  }

  int _countMissingInList(dynamic rawList) {
    if (rawList is! List) {
      return 0;
    }

    var count = 0;
    for (final item in rawList) {
      if (item is! Map) {
        continue;
      }
      final status = (item['status'] ?? 'local').toString();
      if (status == 'deleted') {
        continue;
      }
      final missingLocal = item['missingLocal'] == true;
      if (status == 'missing_local' || missingLocal) {
        count += 1;
      }
    }
    return count;
  }

  bool _isDisplayablePhoto(Map<String, dynamic> photo) {
    final status = (photo['status'] ?? 'local').toString();
    final missingLocal = photo['missingLocal'] == true;
    return status != 'deleted' && status != 'missing_local' && !missingLocal;
  }
}
