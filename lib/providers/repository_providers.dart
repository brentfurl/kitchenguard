import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/cloud_day_note_repository.dart';
import '../data/repositories/cloud_day_schedule_repository.dart';
import '../data/repositories/cloud_job_repository.dart';
import '../data/repositories/day_note_repository.dart';
import '../data/repositories/day_schedule_repository.dart';
import '../data/repositories/job_repository.dart';
import '../data/repositories/local_day_note_repository.dart';
import '../data/repositories/local_day_schedule_repository.dart';
import '../data/repositories/local_job_repository.dart';
import '../storage/app_paths.dart';
import '../storage/atomic_write.dart';
import '../storage/day_note_store.dart';
import '../storage/day_schedule_store.dart';
import '../storage/image_file_store.dart';
import '../storage/job_scanner.dart';
import '../storage/job_store.dart';
import '../storage/video_file_store.dart';
import 'auth_provider.dart';

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

/// Filesystem-only [JobRepository] — always available regardless of auth.
final localJobRepositoryProvider = Provider<LocalJobRepository>((ref) {
  return LocalJobRepository(
    paths: ref.watch(appPathsProvider),
    jobStore: ref.watch(jobStoreProvider),
    jobScanner: ref.watch(jobScannerProvider),
    imageStore: ref.watch(imageStoreProvider),
    videoStore: ref.watch(videoStoreProvider),
  );
});

/// The [JobRepository] exposed to the service layer.
///
/// When authenticated, wraps the local repo in [CloudJobRepository] so that
/// every job save is mirrored to Firestore. When not authenticated, uses the
/// local repo directly.
final jobRepositoryProvider = Provider<JobRepository>((ref) {
  final localRepo = ref.watch(localJobRepositoryProvider);
  final user = ref.watch(authStateProvider).valueOrNull;

  if (user != null) {
    return CloudJobRepository(
      local: localRepo,
      firestore: FirebaseFirestore.instance,
      paths: ref.watch(appPathsProvider),
    );
  }

  return localRepo;
});

/// The [DayNoteRepository] exposed to the service layer.
///
/// When authenticated, uses Firestore (with built-in offline cache).
/// When not authenticated, falls back to the local JSON file.
final dayNoteRepositoryProvider = Provider<DayNoteRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;

  if (user != null) {
    return CloudDayNoteRepository(
      firestore: FirebaseFirestore.instance,
    );
  }

  return LocalDayNoteRepository(
    dayNoteStore: ref.watch(dayNoteStoreProvider),
  );
});

/// Shared [DayScheduleStore] instance.
final dayScheduleStoreProvider = Provider<DayScheduleStore>((ref) {
  return DayScheduleStore(paths: ref.watch(appPathsProvider));
});

/// The [DayScheduleRepository] exposed to the service layer.
///
/// When authenticated, uses Firestore (with built-in offline cache).
/// When not authenticated, falls back to the local JSON file.
final dayScheduleRepositoryProvider = Provider<DayScheduleRepository>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;

  if (user != null) {
    return CloudDayScheduleRepository(
      firestore: FirebaseFirestore.instance,
    );
  }

  return LocalDayScheduleRepository(
    dayScheduleStore: ref.watch(dayScheduleStoreProvider),
  );
});
