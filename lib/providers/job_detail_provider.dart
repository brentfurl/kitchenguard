import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/job.dart';
import 'repository_providers.dart';

/// Loads a single [Job] for the detail screen.
///
/// Parameterized by the job directory path. After mutations,
/// `ref.invalidate(jobDetailProvider(path))` triggers a reload.
class JobDetailNotifier extends FamilyAsyncNotifier<Job, String> {
  @override
  FutureOr<Job> build(String arg) async {
    final job = await ref.read(jobRepositoryProvider).loadJob(Directory(arg));
    if (job == null) throw StateError('job.json missing: $arg');
    return job;
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final job =
          await ref.read(jobRepositoryProvider).loadJob(Directory(arg));
      if (job == null) throw StateError('job.json missing: $arg');
      return job;
    });
  }
}

final jobDetailProvider =
    AsyncNotifierProvider.family<JobDetailNotifier, Job, String>(
  JobDetailNotifier.new,
);
