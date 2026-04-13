import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/models/job.dart';
import '../domain/models/photo_record.dart';

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

  /// Soft-delete a single photo within a unit.
  ///
  /// Re-reads the job from Firestore to minimise the stale-data window, marks
  /// the target [PhotoRecord] as `deleted`, then writes the updated `units`
  /// array back via [updateFields]. Follows the same read-then-write pattern
  /// used by the notes CRUD operations.
  Future<void> softDeletePhoto({
    required String jobId,
    required String unitId,
    required String phase,
    required String photoId,
  }) async {
    final job = await loadJob(jobId);
    if (job == null) return;

    final now = DateTime.now().toUtc().toIso8601String();

    final updatedUnits = job.units.map((unit) {
      if (unit.unitId != unitId) return unit;

      List<PhotoRecord> markDeleted(List<PhotoRecord> photos) {
        return photos.map((p) {
          if (p.photoId != photoId) return p;
          if (p.isDeleted) return p;
          return p.copyWith(status: 'deleted', deletedAt: now);
        }).toList();
      }

      if (phase == 'before') {
        return unit.copyWith(photosBefore: markDeleted(unit.photosBefore));
      }
      return unit.copyWith(photosAfter: markDeleted(unit.photosAfter));
    }).toList();

    await updateFields(jobId, {
      'units': updatedUnits.map((u) => u.toJson()).toList(),
    });
  }

  /// Delete a job from Firestore.
  Future<void> deleteJob(String jobId) async {
    await _jobs.doc(jobId).delete();
  }
}
