import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../storage/job_scanner.dart';
import 'repository_providers.dart';

/// Holds the list of all scanned jobs.
///
/// Screens call `ref.watch(jobListProvider)` to get loading/error/data states.
/// After mutations, call `ref.invalidate(jobListProvider)` to reload.
class JobListNotifier extends AsyncNotifier<List<JobScanResult>> {
  @override
  FutureOr<List<JobScanResult>> build() {
    return ref.read(jobRepositoryProvider).loadAllJobs();
  }

  /// Force a reload from disk (e.g. after returning from job detail).
  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(jobRepositoryProvider).loadAllJobs(),
    );
  }

  /// Pulls remote jobs (merge with local), then reloads the list.
  ///
  /// Used by pull-to-refresh. No-op if the repository is local-only.
  Future<void> pullAndReload() async {
    await ref.read(jobRepositoryProvider).pullFromCloud();
    await reload();
  }
}

final jobListProvider =
    AsyncNotifierProvider<JobListNotifier, List<JobScanResult>>(
  JobListNotifier.new,
);
