import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'job_store.dart';

class JobScanResult {
  const JobScanResult({
    required this.jobDir,
    required this.jobJson,
    required this.jobData,
  });

  final Directory jobDir;
  final File jobJson;
  final Map<String, dynamic> jobData;
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
        final summary = await _reconcilePhotosFromDisk(
          jobDir: jobDir,
          jobData: jobData,
        );
        if (summary.recoveredCount > 0 || summary.statusChangeCount > 0) {
          await jobStore.writeJobJson(jobJsonFile, jobData);
          if (summary.recoveredCount > 0) {
            developer.log(
              'Recovered ${summary.recoveredCount} orphan photo(s) for ${jobDir.path}',
              name: 'JobScanner',
            );
          }
        }

        results.add(
          JobScanResult(jobDir: jobDir, jobJson: jobJsonFile, jobData: jobData),
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
      final category = _categoryForUnitType(unitType);
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
    }

    return _ReconcileSummary(
      recoveredCount: recovered,
      statusChangeCount: statusChanges,
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

    if (added > 0 || statusChanges > 0) {
      unit[photosKey] = photosRaw;
    }
    return _ReconcileSummary(
      recoveredCount: added,
      statusChangeCount: statusChanges,
    );
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
      if (!existsOnDisk) {
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

  String? _categoryForUnitType(String unitType) {
    switch (unitType.trim().toLowerCase()) {
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
  });

  final int recoveredCount;
  final int statusChangeCount;
}
