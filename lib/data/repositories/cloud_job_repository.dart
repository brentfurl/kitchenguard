import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../../domain/merge/job_merger.dart';
import '../../domain/models/job.dart';
import '../../domain/models/unit.dart';
import '../../storage/app_paths.dart';
import '../../storage/job_scanner.dart';
import 'job_repository.dart';

/// Firestore-aware [JobRepository] that wraps a local implementation.
///
/// All filesystem operations (photo/video persistence, folder creation)
/// delegate to [_local]. On metadata writes (`saveJob`, `createJobFolder`,
/// `deleteJob`) the job document is also mirrored to Firestore so that
/// scheduling data is available across devices.
///
/// Reads always come from the local filesystem — cloud-to-local pull
/// happens via [fetchCloudJobs] / [fetchCloudJob], triggered on
/// app-open or pull-to-refresh.
class CloudJobRepository implements JobRepository {
  CloudJobRepository({
    required JobRepository local,
    required FirebaseFirestore firestore,
    required AppPaths paths,
  })  : _local = local,
        _paths = paths,
        _jobs = firestore.collection('jobs');

  final JobRepository _local;
  final AppPaths _paths;
  final CollectionReference<Map<String, dynamic>> _jobs;
  final Uuid _uuid = const Uuid();

  // ---------------------------------------------------------------------------
  // Read — always local (fast, offline-first)
  // ---------------------------------------------------------------------------

  @override
  Future<List<JobScanResult>> loadAllJobs() => _local.loadAllJobs();

  @override
  Future<Job?> loadJob(Directory jobDir) => _local.loadJob(jobDir);

  // ---------------------------------------------------------------------------
  // Write — local first, then mirror to Firestore
  // ---------------------------------------------------------------------------

  @override
  Future<Job> saveJob(Directory jobDir, Job job) async {
    final saved = await _local.saveJob(jobDir, job);
    _syncToFirestore(saved);
    return saved;
  }

  @override
  Future<Directory> createJobFolder({
    required String jobPath,
    required Job job,
  }) async {
    final dir = await _local.createJobFolder(jobPath: jobPath, job: job);
    _syncToFirestore(job);
    return dir;
  }

  @override
  Future<void> deleteJob(Directory jobDir) async {
    final job = await _local.loadJob(jobDir);
    await _local.deleteJob(jobDir);
    if (job != null) {
      _deleteFromFirestore(job.jobId);
    }
  }

  // ---------------------------------------------------------------------------
  // Filesystem-only — straight pass-through
  // ---------------------------------------------------------------------------

  @override
  Future<File> persistPhoto({
    required Directory jobDir,
    required String unitType,
    required String unitFolderName,
    required String phase,
    required File sourceImageFile,
  }) {
    return _local.persistPhoto(
      jobDir: jobDir,
      unitType: unitType,
      unitFolderName: unitFolderName,
      phase: phase,
      sourceImageFile: sourceImageFile,
    );
  }

  @override
  Future<File> persistVideo({
    required Directory jobDir,
    required String kind,
    required String fileBaseName,
    required File sourceVideoFile,
  }) {
    return _local.persistVideo(
      jobDir: jobDir,
      kind: kind,
      fileBaseName: fileBaseName,
      sourceVideoFile: sourceVideoFile,
    );
  }

  // ---------------------------------------------------------------------------
  // Cloud pull helpers (used by sync / pull-to-refresh)
  // ---------------------------------------------------------------------------

  /// Fetches all job documents from Firestore.
  Future<List<Job>> fetchCloudJobs() async {
    final snapshot = await _jobs.get();
    return snapshot.docs
        .map((doc) => Job.fromJson(doc.data()))
        .toList();
  }

  /// Fetches a single job from Firestore by [jobId].
  Future<Job?> fetchCloudJob(String jobId) async {
    final doc = await _jobs.doc(jobId).get();
    if (!doc.exists || doc.data() == null) return null;
    return Job.fromJson(doc.data()!);
  }

  // ---------------------------------------------------------------------------
  // Real-time stream (Phase 7)
  // ---------------------------------------------------------------------------

  @override
  Stream<List<Job>> watchCloudJobs() {
    return _jobs.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Job.fromJson(doc.data()))
          .toList();
    });
  }

  // ---------------------------------------------------------------------------
  // Cloud pull + merge
  // ---------------------------------------------------------------------------

  /// Fetches all jobs from Firestore and reconciles with local data.
  ///
  /// Delegates to [mergeCloudJobs] after fetching.
  @override
  Future<int> pullFromCloud() async {
    try {
      final cloudJobs = await fetchCloudJobs();
      return await mergeCloudJobs(cloudJobs);
    } catch (e, st) {
      developer.log(
        'pullFromCloud failed: $e',
        name: 'CloudJobRepository',
        error: e,
        stackTrace: st,
      );
      return 0;
    }
  }

  /// Merges [cloudJobs] with local data.
  ///
  /// **Existing local jobs** are merged using append-only union for
  /// documentation data and last-write-wins for scheduling fields.
  ///
  /// **Cloud-only jobs** (no local folder) are provisioned locally so
  /// they appear in the job list. Media files stay cloud-only and are
  /// viewable via [CloudAwareImage] / network video playback (Step 4e).
  ///
  /// Results are saved to the local filesystem only — **except** when
  /// the merge detects that Firestore is missing documentation records
  /// that exist locally. In that case the merged result is pushed back
  /// to Firestore to self-heal overwrites from other clients (e.g. the
  /// web console using partial updates on a stale copy). This is safe
  /// from infinite loops because the next snapshot will match the local
  /// version, so no further pushback occurs.
  @override
  Future<int> mergeCloudJobs(List<Job> cloudJobs) async {
    try {
      final localResults = await _local.loadAllJobs();
      final localMap = <String, JobScanResult>{};
      for (final result in localResults) {
        localMap[result.job.jobId] = result;
      }
      final cloudIds = cloudJobs.map((j) => j.jobId).toSet();

      var mergedCount = 0;
      for (final cloudJob in cloudJobs) {
        final localResult = localMap[cloudJob.jobId];

        if (localResult != null) {
          final merged = JobMerger.merge(
            local: localResult.job,
            cloud: cloudJob,
          );
          final hydrated = _withAutoPopulatedUnitsFromCounts(merged);
          final saved = await _local.saveJob(localResult.jobDir, hydrated);
          await _provisionUnitFolders(localResult.jobDir, saved);

          if (_cloudIsMissingRecords(saved, cloudJob)) {
            developer.log(
              'Pushback: cloud missing records for '
              '${saved.restaurantName} — re-syncing to Firestore',
              name: 'CloudJobRepository',
            );
            _syncToFirestore(saved);
          }
        } else {
          await _provisionCloudOnlyJob(cloudJob);
        }
        mergedCount++;
      }

      // Prune local jobs deleted in cloud so deletions propagate cross-device.
      var prunedCount = 0;
      for (final localResult in localResults) {
        if (cloudIds.contains(localResult.job.jobId)) continue;
        try {
          await _local.deleteJob(localResult.jobDir);
          prunedCount++;
          developer.log(
            'Pruned local job missing from cloud: ${localResult.job.restaurantName} (${localResult.job.jobId})',
            name: 'CloudJobRepository',
          );
        } catch (e, st) {
          developer.log(
            'Failed to prune local job ${localResult.job.jobId}: $e',
            name: 'CloudJobRepository',
            error: e,
            stackTrace: st,
          );
        }
      }

      if (prunedCount > 0) {
        developer.log(
          'Pruned $prunedCount local job(s) deleted from cloud',
          name: 'CloudJobRepository',
        );
      }

      return mergedCount + prunedCount;
    } catch (e, st) {
      developer.log(
        'mergeCloudJobs failed: $e',
        name: 'CloudJobRepository',
        error: e,
        stackTrace: st,
      );
      return 0;
    }
  }

  /// Creates a local folder for a job that exists only in Firestore.
  ///
  /// Uses `{root}/{sanitized_name}_{jobId_suffix}` for the folder path
  /// to guarantee uniqueness. The job is saved via [_local] only (no
  /// re-push to Firestore).
  Future<void> _provisionCloudOnlyJob(Job cloudJob) async {
    try {
      final rootPath = await _paths.getRootPath();
      final safeName = _paths.sanitizeName(cloudJob.restaurantName);
      final idSuffix = cloudJob.jobId.length >= 8
          ? cloudJob.jobId.substring(0, 8)
          : cloudJob.jobId;
      final folderName = '${safeName}_$idSuffix';
      final jobPath = p.join(rootPath, folderName);

      if (await Directory(jobPath).exists()) return;

      final hydrated = _withAutoPopulatedUnitsFromCounts(cloudJob);
      final jobDir =
          await _local.createJobFolder(jobPath: jobPath, job: hydrated);
      await _provisionUnitFolders(jobDir, hydrated);
      developer.log(
        'Provisioned cloud-only job: ${cloudJob.restaurantName} → $folderName',
        name: 'CloudJobRepository',
      );
    } catch (e, st) {
      developer.log(
        'Failed to provision cloud-only job ${cloudJob.jobId}: $e',
        name: 'CloudJobRepository',
        error: e,
        stackTrace: st,
      );
    }
  }

  /// Creates Before/ and After/ folders for any units whose directories
  /// don't exist locally. Needed when cloud-only units arrive via merge.
  Future<void> _provisionUnitFolders(Directory jobDir, Job job) async {
    for (final unit in job.units) {
      final category = AppPaths.categoryForUnitType(unit.type);
      if (category == null || unit.unitFolderName.isEmpty) continue;

      final unitPath = p.join(jobDir.path, category, unit.unitFolderName);
      final beforeDir = Directory(p.join(unitPath, AppPaths.beforeFolderName));
      final afterDir = Directory(p.join(unitPath, AppPaths.afterFolderName));

      if (!await beforeDir.exists()) {
        await beforeDir.create(recursive: true);
        developer.log(
          'Provisioned unit folder: $category/${unit.unitFolderName}',
          name: 'CloudJobRepository',
        );
      }
      if (!await afterDir.exists()) {
        await afterDir.create(recursive: true);
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Stale-cloud detection
  // ---------------------------------------------------------------------------

  /// Returns true when [cloud] has fewer documentation records (photos,
  /// videos, notes) than [merged]. This indicates Firestore was overwritten
  /// with stale data (e.g. a web console edit on an old snapshot).
  bool _cloudIsMissingRecords(Job merged, Job cloud) {
    return _docRecordCount(merged) > _docRecordCount(cloud);
  }

  /// Counts total documentation records across all units, pre-clean,
  /// videos, and notes.
  static int _docRecordCount(Job job) {
    var count = 0;
    for (final u in job.units) {
      count += u.photosBefore.length + u.photosAfter.length;
    }
    count += job.preCleanLayoutPhotos.length;
    count += job.videos.exit.length + job.videos.other.length;
    count += job.notes.length + job.managerNotes.length;
    return count;
  }

  // ---------------------------------------------------------------------------
  // Internal
  // ---------------------------------------------------------------------------

  Job _withAutoPopulatedUnitsFromCounts(Job job) {
    if (job.units.isNotEmpty) return job;

    final hoodCount = job.hoodCount ?? 0;
    final fanCount = job.fanCount ?? 0;
    if (hoodCount <= 0 && fanCount <= 0) return job;

    final generatedUnits = <Unit>[];
    for (var i = 1; i <= hoodCount; i++) {
      generatedUnits.add(_buildAutoUnit(type: 'hood', index: i));
    }
    for (var i = 1; i <= fanCount; i++) {
      generatedUnits.add(_buildAutoUnit(type: 'fan', index: i));
    }

    developer.log(
      'Auto-populated ${generatedUnits.length} unit(s) from counts for ${job.jobId}',
      name: 'CloudJobRepository',
    );
    return job.copyWith(units: generatedUnits);
  }

  Unit _buildAutoUnit({required String type, required int index}) {
    final unitId = _uuid.v4();
    final unitName = '$type $index';
    return Unit(
      unitId: unitId,
      type: type,
      name: unitName,
      unitFolderName: _paths.unitFolderName(unitName: unitName, unitId: unitId),
      isComplete: false,
      photosBefore: const [],
      photosAfter: const [],
    );
  }

  void _syncToFirestore(Job job) {
    _jobs.doc(job.jobId).set(job.toJson()).catchError((Object e) {
      developer.log(
        'Firestore job sync failed (will retry when online)',
        name: 'CloudJobRepository',
        error: e,
      );
    });
  }

  void _deleteFromFirestore(String jobId) {
    _jobs.doc(jobId).delete().catchError((Object e) {
      developer.log(
        'Firestore job delete failed',
        name: 'CloudJobRepository',
        error: e,
      );
    });
  }
}
