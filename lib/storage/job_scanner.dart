import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../domain/models/job.dart';
import 'app_paths.dart';
import 'job_store.dart';

const _uuid = Uuid();

class JobScanResult {
  const JobScanResult({
    required this.jobDir,
    required this.jobJson,
    required this.job,
  });

  final Directory jobDir;
  final File jobJson;
  final Job job;

  /// Backward-compatible accessor for callers not yet migrated to the typed model.
  Map<String, dynamic> get jobData => job.toJson();
}

/// Scans job folders and loads valid `job.json` files.
class JobScanner {
  JobScanner({required this.paths, required this.jobStore});

  final AppPaths paths;
  final JobStore jobStore;

  Future<List<JobScanResult>> scanJobs() async {
    final rootPath = await paths.getRootPath();
    final rootDir = Directory(rootPath);

    if (!await rootDir.exists()) {
      return const [];
    }

    final results = <JobScanResult>[];
    final entities = await rootDir.list(followLinks: false).toList();
    final jobDirs = entities.whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));

    for (final jobDir in jobDirs) {
      final jobJsonFile = File(p.join(jobDir.path, 'job.json'));

      try {
        await _recoverTempJobJsonIfPossible(jobDir, jobJsonFile);

        final jobData = await jobStore.readJobJson(jobJsonFile);
        if (jobData == null) {
          continue;
        }

        final reconcileSummary = await _reconcilePhotosFromDisk(
          jobDir: jobDir,
          jobData: jobData,
        );
        final backfilledCount = _backfillMissingIds(jobData);

        Job job = Job.fromJson(jobData);

        if (reconcileSummary.recoveredCount > 0 ||
            reconcileSummary.statusChangeCount > 0 ||
            reconcileSummary.dedupedCount > 0 ||
            backfilledCount > 0) {
          job = await jobStore.writeJob(jobJsonFile, job);
          if (reconcileSummary.recoveredCount > 0) {
            developer.log(
              'Recovered ${reconcileSummary.recoveredCount} orphan photo(s) for ${jobDir.path}',
              name: 'JobScanner',
            );
          }
          if (reconcileSummary.dedupedCount > 0) {
            developer.log(
              'Deduped ${reconcileSummary.dedupedCount} duplicate photo record(s) for ${jobDir.path}',
              name: 'JobScanner',
            );
          }
          if (backfilledCount > 0) {
            developer.log(
              'Backfilled $backfilledCount missing ID(s) for ${jobDir.path}',
              name: 'JobScanner',
            );
          }
        }

        results.add(
          JobScanResult(jobDir: jobDir, jobJson: jobJsonFile, job: job),
        );
      } catch (error) {
        developer.log(
          'Skipping job folder ${jobDir.path}: $error',
          name: 'JobScanner',
        );
      }
    }

    return results;
  }

  Future<void> _recoverTempJobJsonIfPossible(
    Directory jobDir,
    File jobJsonFile,
  ) async {
    final tempFile = File(p.join(jobDir.path, 'job.json.tmp'));
    if (!await tempFile.exists()) {
      return;
    }

    try {
      await _readJsonMap(tempFile);
    } catch (error) {
      developer.log(
        'Found invalid temp JSON at ${tempFile.path}; leaving as-is. Error: $error',
        name: 'JobScanner',
      );
      return;
    }

    if (await jobJsonFile.exists()) {
      await jobJsonFile.delete();
    }
    await tempFile.rename(jobJsonFile.path);
  }

  Future<Map<String, dynamic>> _readJsonMap(File file) async {
    final raw = await file.readAsString();
    final decoded = jsonDecode(raw);

    if (decoded is! Map<String, dynamic>) {
      throw FormatException(
        'Expected JSON object in ${file.path}, got ${decoded.runtimeType}.',
      );
    }

    return decoded;
  }

  /// Backfills missing [photoId] and [videoId] values using UUID v4.
  ///
  /// Also upgrades [schemaVersion] to 2 when IDs are generated.
  /// Returns the total number of IDs generated.
  int _backfillMissingIds(Map<String, dynamic> jobData) {
    var count = 0;

    final unitsRaw = jobData['units'];
    if (unitsRaw is List) {
      for (final unitRaw in unitsRaw) {
        if (unitRaw is Map) {
          count += _backfillPhotoIds(unitRaw['photosBefore']);
          count += _backfillPhotoIds(unitRaw['photosAfter']);
        }
      }
    }

    count += _backfillPhotoIds(jobData['preCleanLayoutPhotos']);

    final videosRaw = jobData['videos'];
    if (videosRaw is Map) {
      count += _backfillVideoIds(videosRaw['exit']);
      count += _backfillVideoIds(videosRaw['other']);
    }

    if (count > 0 && ((jobData['schemaVersion'] as int?) ?? 1) < 2) {
      jobData['schemaVersion'] = 2;
    }

    return count;
  }

  int _backfillPhotoIds(dynamic photos) {
    if (photos is! List) return 0;
    var count = 0;
    for (final photo in photos) {
      if (photo is Map) {
        final id = (photo['photoId'] ?? '').toString().trim();
        if (id.isEmpty) {
          photo['photoId'] = _uuid.v4();
          count++;
        }
      }
    }
    return count;
  }

  int _backfillVideoIds(dynamic videos) {
    if (videos is! List) return 0;
    var count = 0;
    for (final video in videos) {
      if (video is Map) {
        final id = (video['videoId'] ?? '').toString().trim();
        if (id.isEmpty) {
          video['videoId'] = _uuid.v4();
          count++;
        }
      }
    }
    return count;
  }

  Future<_ReconcileSummary> _reconcilePhotosFromDisk({
    required Directory jobDir,
    required Map<String, dynamic> jobData,
  }) async {
    final unitsRaw = jobData['units'];
    if (unitsRaw is! List) {
      return const _ReconcileSummary();
    }

    var recovered = 0;
    var statusChanges = 0;
    var deduped = 0;
    for (var i = 0; i < unitsRaw.length; i++) {
      final unitRaw = unitsRaw[i];
      if (unitRaw is! Map) {
        continue;
      }

      final unit = unitRaw is Map<String, dynamic>
          ? unitRaw
          : Map<String, dynamic>.from(unitRaw);
      if (unitRaw is! Map<String, dynamic>) {
        unitsRaw[i] = unit;
      }

      final unitType = (unit['type'] ?? '').toString();
      final unitName = (unit['name'] ?? '').toString();
      final unitId = (unit['unitId'] ?? '').toString();
      final category = AppPaths.categoryForUnitType(unitType);
      if (category == null || unitName.trim().isEmpty) {
        continue;
      }

      final unitFolders = _candidateUnitFolders(
        unitName: unitName,
        unitId: unitId,
        storedUnitFolderName: (unit['unitFolderName'] ?? '').toString(),
      );
      final beforeSummary = await _reconcilePhase(
        jobDir: jobDir,
        category: category,
        unitFolders: unitFolders,
        phaseFolder: AppPaths.beforeFolderName,
        photosKey: 'photosBefore',
        unit: unit,
      );
      recovered += beforeSummary.recoveredCount;
      statusChanges += beforeSummary.statusChangeCount;
      deduped += beforeSummary.dedupedCount;

      final afterSummary = await _reconcilePhase(
        jobDir: jobDir,
        category: category,
        unitFolders: unitFolders,
        phaseFolder: AppPaths.afterFolderName,
        photosKey: 'photosAfter',
        unit: unit,
      );
      recovered += afterSummary.recoveredCount;
      statusChanges += afterSummary.statusChangeCount;
      deduped += afterSummary.dedupedCount;
    }

    return _ReconcileSummary(
      recoveredCount: recovered,
      statusChangeCount: statusChanges,
      dedupedCount: deduped,
    );
  }

  Future<_ReconcileSummary> _reconcilePhase({
    required Directory jobDir,
    required String category,
    required List<String> unitFolders,
    required String phaseFolder,
    required String photosKey,
    required Map<String, dynamic> unit,
  }) async {
    final photosRaw = (unit[photosKey] as List?) ?? <dynamic>[];

    final diskFileNames = <String>{};
    final existingNames = <String>{};
    for (final entry in photosRaw) {
      if (entry is Map && entry['fileName'] != null) {
        existingNames.add(entry['fileName'].toString());
      }
    }

    var added = 0;
    final phaseDirs = <Directory>[];
    final seenPhasePaths = <String>{};
    for (final unitFolder in unitFolders) {
      if (unitFolder.isEmpty) {
        continue;
      }
      final dir = Directory(
        p.join(jobDir.path, category, unitFolder, phaseFolder),
      );
      if (!await dir.exists()) {
        continue;
      }
      if (seenPhasePaths.add(dir.path)) {
        phaseDirs.add(dir);
      }
    }

    for (final dir in phaseDirs) {
      await for (final entity in dir.list(followLinks: false)) {
        if (entity is! File) {
          continue;
        }

        final fileName = p.basename(entity.path);
        diskFileNames.add(fileName);
        if (!_isImageFileName(fileName) || existingNames.contains(fileName)) {
          continue;
        }

        final modifiedUtc = (await entity.lastModified())
            .toUtc()
            .toIso8601String();
        final relativePath = p
            .relative(entity.path, from: jobDir.path)
            .replaceAll('\\', '/');

        photosRaw.add(<String, dynamic>{
          'fileName': fileName,
          'relativePath': relativePath,
          'capturedAt': modifiedUtc,
          'status': 'local',
          'recovered': true,
          'syncStatus': 'pending',
        });
        existingNames.add(fileName);
        added += 1;
      }
    }

    final statusChanges = await _markMissingLocal(
      jobDir: jobDir,
      photosRaw: photosRaw,
      diskFileNames: diskFileNames,
    );
    final dedupedCount = _dedupePhotoRecordsByRelativePath(photosRaw);

    if (added > 0 || statusChanges > 0 || dedupedCount > 0) {
      unit[photosKey] = photosRaw;
    }
    return _ReconcileSummary(
      recoveredCount: added,
      statusChangeCount: statusChanges,
      dedupedCount: dedupedCount,
    );
  }

  int _dedupePhotoRecordsByRelativePath(List photosRaw) {
    final grouped = <String, List<_IndexedPhotoEntry>>{};
    for (var i = 0; i < photosRaw.length; i++) {
      final entry = photosRaw[i];
      if (entry is! Map) continue;
      final map = entry is Map<String, dynamic>
          ? entry
          : Map<String, dynamic>.from(entry);
      if (entry is! Map<String, dynamic>) {
        photosRaw[i] = map;
      }
      final relativePath = (map['relativePath'] ?? '').toString().trim();
      if (relativePath.isEmpty) continue;
      final normalizedPath = relativePath.replaceAll('\\', '/');
      grouped
          .putIfAbsent(normalizedPath, () => [])
          .add(_IndexedPhotoEntry(index: i, entry: map));
    }

    final removeIndexes = <int>{};
    for (final entries in grouped.values) {
      if (entries.length <= 1) continue;

      var winner = entries.first;
      for (final candidate in entries.skip(1)) {
        if (_isPreferredPhotoEntry(candidate.entry, winner.entry)) {
          winner = candidate;
        }
      }

      for (final candidate in entries) {
        if (candidate.index == winner.index) continue;
        _mergePhotoMetadata(target: winner.entry, source: candidate.entry);
        removeIndexes.add(candidate.index);
      }
    }

    if (removeIndexes.isEmpty) return 0;

    final sorted = removeIndexes.toList()..sort((a, b) => b.compareTo(a));
    for (final idx in sorted) {
      photosRaw.removeAt(idx);
    }
    return removeIndexes.length;
  }

  bool _isPreferredPhotoEntry(
    Map<String, dynamic> candidate,
    Map<String, dynamic> current,
  ) {
    final candidateRank = _photoEntryRank(candidate);
    final currentRank = _photoEntryRank(current);
    if (candidateRank != currentRank) {
      return candidateRank > currentRank;
    }

    final candidateCaptured = DateTime.tryParse(
      (candidate['capturedAt'] ?? '').toString(),
    );
    final currentCaptured = DateTime.tryParse(
      (current['capturedAt'] ?? '').toString(),
    );
    if (candidateCaptured != null && currentCaptured != null) {
      if (candidateCaptured.isAfter(currentCaptured)) return true;
      if (candidateCaptured.isBefore(currentCaptured)) return false;
    } else if (candidateCaptured != null && currentCaptured == null) {
      return true;
    } else if (candidateCaptured == null && currentCaptured != null) {
      return false;
    }

    final candidateRecovered = candidate['recovered'] == true;
    final currentRecovered = current['recovered'] == true;
    if (candidateRecovered != currentRecovered) {
      return !candidateRecovered;
    }

    final candidateHasId = (candidate['photoId'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    final currentHasId = (current['photoId'] ?? '')
        .toString()
        .trim()
        .isNotEmpty;
    if (candidateHasId != currentHasId) {
      return candidateHasId;
    }

    return false;
  }

  int _photoEntryRank(Map<String, dynamic> entry) {
    final status = (entry['status'] ?? '').toString();
    final missingLocal = entry['missingLocal'] == true;
    final isActive = status == 'local' && !missingLocal;
    final isDeleted = status == 'deleted';

    final lifecycleRank = isActive
        ? 3
        : (isDeleted ? 0 : (status == 'local' ? 2 : 1));

    final syncStatus = (entry['syncStatus'] ?? '').toString();
    const syncRanks = <String, int>{
      'synced': 4,
      'uploading': 3,
      'error': 2,
      'pending': 1,
    };
    final syncRank = syncRanks[syncStatus] ?? 0;
    final hasCloudUrl = (entry['cloudUrl'] ?? '').toString().trim().isNotEmpty;
    final hasSubPhase = (entry['subPhase'] ?? '').toString().trim().isNotEmpty;

    return lifecycleRank * 100 +
        syncRank * 10 +
        (hasCloudUrl ? 2 : 0) +
        (hasSubPhase ? 1 : 0);
  }

  void _mergePhotoMetadata({
    required Map<String, dynamic> target,
    required Map<String, dynamic> source,
  }) {
    final targetSyncRank = _syncRank((target['syncStatus'] ?? '').toString());
    final sourceSyncRank = _syncRank((source['syncStatus'] ?? '').toString());
    if (sourceSyncRank > targetSyncRank) {
      target['syncStatus'] = source['syncStatus'];
      if ((source['cloudUrl'] ?? '').toString().trim().isNotEmpty) {
        target['cloudUrl'] = source['cloudUrl'];
      }
      if ((source['uploadedBy'] ?? '').toString().trim().isNotEmpty) {
        target['uploadedBy'] = source['uploadedBy'];
      }
    } else if ((target['cloudUrl'] ?? '').toString().trim().isEmpty &&
        (source['cloudUrl'] ?? '').toString().trim().isNotEmpty) {
      target['cloudUrl'] = source['cloudUrl'];
      if ((source['uploadedBy'] ?? '').toString().trim().isNotEmpty) {
        target['uploadedBy'] = source['uploadedBy'];
      }
    }

    if ((target['subPhase'] ?? '').toString().trim().isEmpty &&
        (source['subPhase'] ?? '').toString().trim().isNotEmpty) {
      target['subPhase'] = source['subPhase'];
    }
    if ((target['photoId'] ?? '').toString().trim().isEmpty &&
        (source['photoId'] ?? '').toString().trim().isNotEmpty) {
      target['photoId'] = source['photoId'];
    }
    if ((target['fileName'] ?? '').toString().trim().isEmpty &&
        (source['fileName'] ?? '').toString().trim().isNotEmpty) {
      target['fileName'] = source['fileName'];
    }
  }

  int _syncRank(String syncStatus) {
    switch (syncStatus) {
      case 'synced':
        return 4;
      case 'uploading':
        return 3;
      case 'error':
        return 2;
      case 'pending':
        return 1;
      default:
        return 0;
    }
  }

  Future<int> _markMissingLocal({
    required Directory jobDir,
    required List photosRaw,
    required Set<String> diskFileNames,
  }) async {
    var statusChanges = 0;
    for (final entry in photosRaw) {
      if (entry is! Map) {
        continue;
      }

      var existsOnDisk = false;
      final relativePath = (entry['relativePath'] ?? '').toString().trim();
      if (relativePath.isNotEmpty) {
        final candidate = File(p.join(jobDir.path, relativePath));
        try {
          existsOnDisk = await candidate.exists();
        } on FileSystemException {
          existsOnDisk = false;
        }
      }

      final fileName = (entry['fileName'] ?? '').toString();
      if (!existsOnDisk && fileName.isNotEmpty) {
        existsOnDisk = diskFileNames.contains(fileName);
      }

      final status = (entry['status'] ?? '').toString();
      final hasCloudUrl = (entry['cloudUrl'] ?? '').toString().isNotEmpty;
      final hasSync = (entry['syncStatus'] ?? '').toString().isNotEmpty;
      if (!existsOnDisk && !hasCloudUrl && !hasSync) {
        if (status != 'missing_local' || entry['missingLocal'] != true) {
          entry['status'] = 'missing_local';
          entry['missingLocal'] = true;
          statusChanges += 1;
        }
      } else if (status == 'missing_local' || entry['missingLocal'] == true) {
        entry['status'] = 'local';
        entry.remove('missingLocal');
        statusChanges += 1;
      }
    }
    return statusChanges;
  }

  List<String> _candidateUnitFolders({
    required String unitName,
    required String unitId,
    required String storedUnitFolderName,
  }) {
    final candidates = <String>[];
    void addIfNotEmpty(String value) {
      final trimmed = value.trim();
      if (trimmed.isNotEmpty && !candidates.contains(trimmed)) {
        candidates.add(trimmed);
      }
    }

    addIfNotEmpty(storedUnitFolderName);
    if (unitId.trim().isNotEmpty) {
      addIfNotEmpty(paths.unitFolderName(unitName: unitName, unitId: unitId));
    }
    addIfNotEmpty(paths.sanitizeName(unitName));
    return candidates;
  }

  bool _isImageFileName(String fileName) {
    final lower = fileName.toLowerCase();
    return lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.png');
  }
}

class _ReconcileSummary {
  const _ReconcileSummary({
    this.recoveredCount = 0,
    this.statusChangeCount = 0,
    this.dedupedCount = 0,
  });

  final int recoveredCount;
  final int statusChangeCount;
  final int dedupedCount;
}

class _IndexedPhotoEntry {
  const _IndexedPhotoEntry({required this.index, required this.entry});

  final int index;
  final Map<String, dynamic> entry;
}
