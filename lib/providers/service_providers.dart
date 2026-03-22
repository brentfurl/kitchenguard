import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/jobs_service.dart';
import 'repository_providers.dart';

/// The [JobsService] exposed to presentation layers.
///
/// Steps 3-4 will migrate screens to access this through Riverpod notifiers.
/// For now it's provided here so the dependency graph is centralized.
final jobsServiceProvider = Provider<JobsService>((ref) {
  return JobsService(
    paths: ref.watch(appPathsProvider),
    jobStore: ref.watch(jobStoreProvider),
    imageStore: ref.watch(imageStoreProvider),
    videoStore: ref.watch(videoStoreProvider),
    dayNoteStore: ref.watch(dayNoteStoreProvider),
  );
});
