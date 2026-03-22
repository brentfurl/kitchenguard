import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/models/day_schedule.dart';
import 'app_paths.dart';
import 'atomic_write.dart';

/// Reads and writes `day_schedules.json` in the root KitchenCleaningJobs/ directory.
///
/// File format: `{ "YYYY-MM-DD": { DaySchedule json } }`
class DayScheduleStore {
  DayScheduleStore({required AppPaths paths})
      : _fileResolver = (() async {
          final root = await paths.getRootPath();
          return File(p.join(root, 'day_schedules.json'));
        });

  DayScheduleStore.fromFile(File file) : _fileResolver = (() async => file);

  final Future<File> Function() _fileResolver;

  Future<Map<String, DaySchedule>> readAll() async {
    final file = await _fileResolver();

    if (!await file.exists()) return {};

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};

      final result = <String, DaySchedule>{};
      for (final entry in decoded.entries) {
        if (entry.value is! Map<String, dynamic>) continue;
        result[entry.key] =
            DaySchedule.fromJson(entry.value as Map<String, dynamic>);
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  Future<DaySchedule?> readForDate(String date) async {
    final all = await readAll();
    return all[date];
  }

  Future<void> write(Map<String, DaySchedule> allSchedules) async {
    final file = await _fileResolver();
    final json = <String, dynamic>{
      for (final entry in allSchedules.entries)
        entry.key: entry.value.toJson(),
    };
    await atomicWriteString(file, jsonEncode(json));
  }
}
