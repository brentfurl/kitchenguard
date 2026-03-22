import '../../domain/models/day_schedule.dart';

/// Data-access contract for day-schedule persistence.
///
/// Today [LocalDayScheduleRepository] reads/writes `day_schedules.json`.
/// Phase 4 adds a cloud-aware implementation without changing callers.
abstract class DayScheduleRepository {
  Future<Map<String, DaySchedule>> loadAll();
  Future<DaySchedule?> loadForDate(String date);
  Future<void> saveAll(Map<String, DaySchedule> allSchedules);
}
