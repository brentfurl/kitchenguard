import '../../domain/models/day_note.dart';
import '../../storage/day_note_store.dart';
import 'day_note_repository.dart';

/// Filesystem-backed [DayNoteRepository].
///
/// Wraps [DayNoteStore] which reads/writes `day_notes.json`.
class LocalDayNoteRepository implements DayNoteRepository {
  LocalDayNoteRepository({required this.dayNoteStore});

  final DayNoteStore dayNoteStore;

  @override
  Future<Map<String, List<DayNote>>> loadAll() => dayNoteStore.readAll();

  @override
  Future<List<DayNote>> loadForDate(String date) =>
      dayNoteStore.readForDate(date);

  @override
  Future<void> saveAll(Map<String, List<DayNote>> allNotes) =>
      dayNoteStore.write(allNotes);

  @override
  Stream<Map<String, List<DayNote>>>? watchAll() => null;
}
