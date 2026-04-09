import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/job.dart';

/// Firestore-only job repository for the web dashboard.
///
/// Unlike mobile, the web dashboard has no local filesystem. All reads and
/// writes go directly to Firestore. This intentionally does NOT implement the
/// mobile [JobRepository] interface (which uses `dart:io` types).
class WebJobRepository {
  WebJobRepository({FirebaseFirestore? firestore})
      : _jobs = (firestore ?? FirebaseFirestore.instance).collection('jobs');

  final CollectionReference<Map<String, dynamic>> _jobs;

  /// Real-time stream of all jobs.
  Stream<List<Job>> watchAllJobs() {
    return _jobs.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => Job.fromJson(doc.data()))
          .toList();
    });
  }

  /// One-time fetch of all jobs.
  Future<List<Job>> loadAllJobs() async {
    final snapshot = await _jobs.get();
    return snapshot.docs
        .map((doc) => Job.fromJson(doc.data()))
        .toList();
  }

  /// Fetch a single job by ID.
  Future<Job?> loadJob(String jobId) async {
    final doc = await _jobs.doc(jobId).get();
    if (!doc.exists || doc.data() == null) return null;
    return Job.fromJson(doc.data()!);
  }

  /// Real-time stream of a single job.
  Stream<Job?> watchJob(String jobId) {
    return _jobs.doc(jobId).snapshots().map((doc) {
      if (!doc.exists || doc.data() == null) return null;
      return Job.fromJson(doc.data()!);
    });
  }

  /// Create or fully replace a job in Firestore.
  ///
  /// Use only for new job creation. For partial edits (scheduling fields,
  /// notes, completion, etc.) prefer [updateFields] to avoid overwriting
  /// phone-managed documentation data (units, photos, videos).
  Future<Job> saveJob(Job job) async {
    final stamped = job.copyWith(
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await _jobs.doc(stamped.jobId).set(stamped.toJson());
    return stamped;
  }

  /// Partially updates specific fields on a Firestore job document.
  ///
  /// Uses Firestore `update()` so only the provided [fields] are written;
  /// all other fields (especially `units` with photo records) are untouched.
  /// Automatically stamps `updatedAt`.
  Future<void> updateFields(String jobId, Map<String, dynamic> fields) async {
    await _jobs.doc(jobId).update({
      ...fields,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Delete a job from Firestore.
  Future<void> deleteJob(String jobId) async {
    await _jobs.doc(jobId).delete();
  }
}
