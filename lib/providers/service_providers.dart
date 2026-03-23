import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/jobs_service.dart';
import 'repository_providers.dart';

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
  );
});
