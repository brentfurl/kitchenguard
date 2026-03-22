import 'dart:io';

import '../../domain/models/job.dart';
import '../../storage/job_scanner.dart';

/// Data-access contract for job persistence.
///
/// Today [LocalJobRepository] talks to the filesystem.
/// Phase 4 adds a cloud-aware implementation without changing callers.
abstract class JobRepository {
  /// Scans all job folders and returns scan results (with integrity checks).
  Future<List<JobScanResult>> loadAllJobs();

  /// Reads a single typed [Job] from [jobDir].
  ///
  /// Returns null if `job.json` does not exist.
  Future<Job?> loadJob(Directory jobDir);

  /// Writes [job] to [jobDir], stamping `updatedAt`.
  ///
  /// Returns the stamped [Job].
  Future<Job> saveJob(Directory jobDir, Job job);

  /// Creates the job folder structure and writes the initial [job].
  ///
  /// Returns the created [Directory].
  Future<Directory> createJobFolder({
    required String jobPath,
    required Job job,
  });

  /// Deletes [jobDir] and all its contents.
  Future<void> deleteJob(Directory jobDir);

  /// Persists [sourceImageFile] into the correct unit/phase folder.
  ///
  /// Returns the final [File] on disk.
  Future<File> persistPhoto({
    required Directory jobDir,
    required String unitType,
    required String unitFolderName,
    required String phase,
    required File sourceImageFile,
  });

  /// Persists [sourceVideoFile] into the correct video folder.
  ///
  /// Returns the final [File] on disk.
  Future<File> persistVideo({
    required Directory jobDir,
    required String kind,
    required String fileBaseName,
    required File sourceVideoFile,
  });
}
