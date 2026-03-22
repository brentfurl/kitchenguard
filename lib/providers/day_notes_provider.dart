import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/day_note.dart';
import 'repository_providers.dart';

/// Holds all day notes keyed by date, filtered to active-only.
///
/// Screens call `ref.watch(dayNotesProvider)` to get the current state.
/// After mutations, call `ref.invalidate(dayNotesProvider)` to reload.
class DayNotesNotifier
    extends AsyncNotifier<Map<String, List<DayNote>>> {
  @override
  FutureOr<Map<String, List<DayNote>>> build() async {
    final all = await ref.read(dayNoteRepositoryProvider).loadAll();
    return _filterActive(all);
  }

  Future<void> reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final all = await ref.read(dayNoteRepositoryProvider).loadAll();
      return _filterActive(all);
    });
  }

  static Map<String, List<DayNote>> _filterActive(
    Map<String, List<DayNote>> raw,
  ) {
    final active = <String, List<DayNote>>{};
    for (final entry in raw.entries) {
      final list = entry.value.where((n) => n.isActive).toList();
      if (list.isNotEmpty) active[entry.key] = list;
    }
    return active;
  }
}

final dayNotesProvider = AsyncNotifierProvider<DayNotesNotifier,
    Map<String, List<DayNote>>>(
  DayNotesNotifier.new,
);
