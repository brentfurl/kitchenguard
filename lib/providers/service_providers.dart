import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/jobs_service.dart';
import '../services/storage_service.dart';
import '../services/upload_controller.dart';
import '../services/upload_queue.dart';
import 'auth_provider.dart';
import 'repository_providers.dart';

/// Persistent upload queue — always available regardless of auth state.
///
/// Media is enqueued after capture. Processing requires an authenticated
/// [UploadController] (see [uploadControllerProvider]).
final uploadQueueProvider = Provider<UploadQueue>((ref) {
  return UploadQueue(paths: ref.watch(appPathsProvider));
});

/// The [JobsService] exposed to presentation layers.
///
/// All data access flows through repository interfaces, making the
/// cloud swap in Phase 4 transparent to callers.
final jobsServiceProvider = Provider<JobsService>((ref) {
  return JobsService(
    paths: ref.watch(appPathsProvider),
    jobRepository: ref.watch(jobRepositoryProvider),
    dayNoteRepository: ref.watch(dayNoteRepositoryProvider),
    dayScheduleRepository: ref.watch(dayScheduleRepositoryProvider),
    uploadQueue: ref.watch(uploadQueueProvider),
  );
});

/// Shared [StorageService] instance — wraps Firebase Storage.
///
/// Available regardless of auth state; callers should check authentication
/// before invoking uploads.
final storageServiceProvider = Provider<StorageService>((ref) {
  return StorageService();
});

/// [UploadController] for uploading individual photos/videos.
///
/// Only available when authenticated (returns null otherwise).
/// The upload queue (Step 4b) will use this to process each item.
final uploadControllerProvider = Provider<UploadController?>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return null;

  return UploadController(
    storageService: ref.watch(storageServiceProvider),
    jobRepository: ref.watch(jobRepositoryProvider),
    currentUserId: user.uid,
  );
});
