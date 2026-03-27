import 'dart:io';

import 'package:path/path.dart' as p;

import '../../domain/models/job.dart';
import '../../storage/app_paths.dart';
import '../../storage/image_file_store.dart';
import '../../storage/job_scanner.dart';
import '../../storage/job_store.dart';
import '../../storage/video_file_store.dart';
import 'job_repository.dart';

/// Filesystem-backed [JobRepository].
///
/// Wraps the existing storage classes. Phase 4 adds a cloud-aware
/// implementation behind the same interface.
class LocalJobRepository implements JobRepository {
  LocalJobRepository({
    required this.paths,
    required this.jobStore,
    required this.jobScanner,
    required this.imageStore,
    required this.videoStore,
  });

  final AppPaths paths;
  final JobStore jobStore;
  final JobScanner jobScanner;
  final ImageFileStore imageStore;
  final VideoFileStore videoStore;

  @override
  Future<List<JobScanResult>> loadAllJobs() => jobScanner.scanJobs();

  @override
  Future<Job?> loadJob(Directory jobDir) {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    return jobStore.readJob(jobJsonFile);
  }

  @override
  Future<Job> saveJob(Directory jobDir, Job job) {
    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    return jobStore.writeJob(jobJsonFile, job);
  }

  @override
  Future<Directory> createJobFolder({
    required String jobPath,
    required Job job,
  }) async {
    final jobDir = Directory(jobPath);
    await jobDir.create(recursive: true);
    await Directory(p.join(jobDir.path, AppPaths.hoodsCategory))
        .create(recursive: true);
    await Directory(p.join(jobDir.path, AppPaths.fansCategory))
        .create(recursive: true);
    await Directory(p.join(jobDir.path, AppPaths.miscCategory))
        .create(recursive: true);

    final jobJsonFile = File(p.join(jobDir.path, 'job.json'));
    await jobStore.writeJob(jobJsonFile, job);
    return jobDir;
  }

  @override
  Future<void> deleteJob(Directory jobDir) async {
    if (!await jobDir.exists()) return;

    final rootPath = p.normalize(await paths.getRootPath());
    final jobPath = p.normalize(jobDir.path);
    if (!p.isWithin(rootPath, jobPath) && jobPath != rootPath) {
      throw StateError('Refusing to delete path outside jobs root: $jobPath');
    }

    final jobJsonFile = File(p.join(jobPath, 'job.json'));
    if (!await jobJsonFile.exists()) {
      throw StateError('Refusing to delete non-job directory: $jobPath');
    }

    await Directory(jobPath).delete(recursive: true);
  }

  @override
  Future<File> persistPhoto({
    required Directory jobDir,
    required String unitType,
    required String unitFolderName,
    required String phase,
    required File sourceImageFile,
  }) {
    return imageStore.persistPhoto(
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
    return videoStore.persistVideo(
      jobDir: jobDir,
      kind: kind,
      fileBaseName: fileBaseName,
      sourceVideoFile: sourceVideoFile,
    );
  }

  @override
  Future<int> pullFromCloud() async => 0;

  @override
  Future<int> mergeCloudJobs(List<Job> cloudJobs) async => 0;

  @override
  Stream<List<Job>>? watchCloudJobs() => null;
}
