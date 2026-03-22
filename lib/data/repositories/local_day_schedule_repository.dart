import '../../domain/models/day_schedule.dart';
import '../../storage/day_schedule_store.dart';
import 'day_schedule_repository.dart';

/// Filesystem-backed [DayScheduleRepository].
///
/// Wraps [DayScheduleStore] which reads/writes `day_schedules.json`.
class LocalDayScheduleRepository implements DayScheduleRepository {
  LocalDayScheduleRepository({required this.dayScheduleStore});

  final DayScheduleStore dayScheduleStore;

  @override
  Future<Map<String, DaySchedule>> loadAll() => dayScheduleStore.readAll();

  @override
  Future<DaySchedule?> loadForDate(String date) =>
      dayScheduleStore.readForDate(date);

  @override
  Future<void> saveAll(Map<String, DaySchedule> allSchedules) =>
      dayScheduleStore.write(allSchedules);
}
