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
      final status = (map['status'] ?? 'local').toString();
      if (!includeDeleted && status == 'deleted') {
        continue;
      }
      result.add(map);
    }
    return result;
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

    final picked = await picker.pickImage(source: ImageSource.camera);
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
    final picked = await picker.pickVideo(source: ImageSource.camera);
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

  File videoFileFromRelativePath(String relativePath) {
    return File(p.join(jobDir.path, relativePath));
  }

  Future<File> exportJobZip({required String jobDisplayName}) {
    return jobs.exportJobZip(jobDir: jobDir, zipBaseName: jobDisplayName);
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
      final photos = unit[key];
      if (photos is! List) {
        continue;
      }
      for (final photo in photos) {
        if (photo is! Map) {
          continue;
        }
        final status = (photo['status'] ?? 'local').toString();
        if (status == 'deleted') {
          continue;
        }
        count += 1;
      }
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
}
