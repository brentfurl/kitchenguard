import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/day_note_repository.dart';
import '../data/repositories/job_repository.dart';
import '../data/repositories/local_day_note_repository.dart';
import '../data/repositories/local_job_repository.dart';
import '../storage/app_paths.dart';
import '../storage/atomic_write.dart';
import '../storage/day_note_store.dart';
import '../storage/image_file_store.dart';
import '../storage/job_scanner.dart';
import '../storage/job_store.dart';
import '../storage/video_file_store.dart';

/// Shared [AppPaths] instance.
final appPathsProvider = Provider<AppPaths>((ref) => AppPaths());

/// Shared [JobStore] instance.
final jobStoreProvider = Provider<JobStore>((ref) => JobStore());

/// Shared [ImageFileStore] instance.
final imageStoreProvider = Provider<ImageFileStore>((ref) {
  return ImageFileStore(paths: ref.watch(appPathsProvider));
});

/// Shared [VideoFileStore] instance.
final videoStoreProvider = Provider<VideoFileStore>((ref) {
  return VideoFileStore(
    paths: ref.watch(appPathsProvider),
    atomicWrite: atomicWriteBytes,
  );
});

/// Shared [DayNoteStore] instance.
final dayNoteStoreProvider = Provider<DayNoteStore>((ref) {
  return DayNoteStore(paths: ref.watch(appPathsProvider));
});

/// Shared [JobScanner] instance.
final jobScannerProvider = Provider<JobScanner>((ref) {
  return JobScanner(
    paths: ref.watch(appPathsProvider),
    jobStore: ref.watch(jobStoreProvider),
  );
});

/// The [JobRepository] exposed to the service layer.
final jobRepositoryProvider = Provider<JobRepository>((ref) {
  return LocalJobRepository(
    paths: ref.watch(appPathsProvider),
    jobStore: ref.watch(jobStoreProvider),
    jobScanner: ref.watch(jobScannerProvider),
    imageStore: ref.watch(imageStoreProvider),
    videoStore: ref.watch(videoStoreProvider),
  );
});

/// The [DayNoteRepository] exposed to the service layer.
final dayNoteRepositoryProvider = Provider<DayNoteRepository>((ref) {
  return LocalDayNoteRepository(
    dayNoteStore: ref.watch(dayNoteStoreProvider),
  );
});
