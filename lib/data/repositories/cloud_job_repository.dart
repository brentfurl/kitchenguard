import 'dart:developer' as developer;
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/job.dart';
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
  })  : _local = local,
        _jobs = firestore.collection('jobs');

  final JobRepository _local;
  final CollectionReference<Map<String, dynamic>> _jobs;

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
  // Internal
  // ---------------------------------------------------------------------------

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
