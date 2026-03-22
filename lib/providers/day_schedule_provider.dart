import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/day_schedule.dart';
import 'repository_providers.dart';

/// Holds all day schedules keyed by date.
///
/// Screens call `ref.watch(dayScheduleProvider)` to get the current state.
/// After mutations, call `ref.invalidate(dayScheduleProvider)` to reload.
class DayScheduleNotifier
    extends AsyncNotifier<Map<String, DaySchedule>> {
  @override
  FutureOr<Map<String, DaySchedule>> build() async {
    return ref.read(dayScheduleRepositoryProvider).loadAll();
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      return ref.read(dayScheduleRepositoryProvider).loadAll();
    });
  }
}

final dayScheduleProvider = AsyncNotifierProvider<DayScheduleNotifier,
    Map<String, DaySchedule>>(
  DayScheduleNotifier.new,
);
