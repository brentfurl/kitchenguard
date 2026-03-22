import '../../domain/models/day_note.dart';

/// Data-access contract for day-note persistence.
///
/// Today [LocalDayNoteRepository] reads/writes `day_notes.json`.
/// Phase 4 adds a cloud-aware implementation without changing callers.
abstract class DayNoteRepository {
  /// Returns all day notes keyed by date string (YYYY-MM-DD).
  Future<Map<String, List<DayNote>>> loadAll();

  /// Returns notes for a single [date].
  Future<List<DayNote>> loadForDate(String date);

  /// Writes the full [allNotes] map to storage.
  Future<void> saveAll(Map<String, List<DayNote>> allNotes);
}
