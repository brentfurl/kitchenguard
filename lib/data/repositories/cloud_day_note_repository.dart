import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/day_note.dart';
import 'day_note_repository.dart';

/// Firestore-backed [DayNoteRepository].
///
/// Each document in the `dayNotes` collection is keyed by date (YYYY-MM-DD)
/// and contains a `notes` array of embedded [DayNote] objects.
///
/// Firestore's built-in offline persistence (enabled by default on mobile)
/// acts as the local cache, so separate local-file fallback is unnecessary
/// while the user is authenticated.
class CloudDayNoteRepository implements DayNoteRepository {
  CloudDayNoteRepository({required FirebaseFirestore firestore})
      : _dayNotes = firestore.collection('dayNotes');

  final CollectionReference<Map<String, dynamic>> _dayNotes;

  @override
  Future<Map<String, List<DayNote>>> loadAll() async {
    final snapshot = await _dayNotes.get();
    final result = <String, List<DayNote>>{};
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final notes = (data['notes'] as List<dynamic>? ?? [])
          .map((e) => DayNote.fromJson(e as Map<String, dynamic>))
          .toList();
      if (notes.isNotEmpty) {
        result[doc.id] = notes;
      }
    }
    return result;
  }

  @override
  Future<List<DayNote>> loadForDate(String date) async {
    final doc = await _dayNotes.doc(date).get();
    if (!doc.exists || doc.data() == null) return [];
    final data = doc.data()!;
    return (data['notes'] as List<dynamic>? ?? [])
        .map((e) => DayNote.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<void> saveAll(Map<String, List<DayNote>> allNotes) async {
    final batch = _dayNotes.firestore.batch();

    final existing = await _dayNotes.get();
    for (final doc in existing.docs) {
      if (!allNotes.containsKey(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    for (final entry in allNotes.entries) {
      batch.set(_dayNotes.doc(entry.key), {
        'notes': entry.value.map((n) => n.toJson()).toList(),
      });
    }

    await batch.commit();
  }

  @override
  Stream<Map<String, List<DayNote>>> watchAll() {
    return _dayNotes.snapshots().map((snapshot) {
      final result = <String, List<DayNote>>{};
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final notes = (data['notes'] as List<dynamic>? ?? [])
            .map((e) => DayNote.fromJson(e as Map<String, dynamic>))
            .toList();
        if (notes.isNotEmpty) {
          result[doc.id] = notes;
        }
      }
      return result;
    });
  }
}
