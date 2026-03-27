import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/models/day_schedule.dart';
import 'day_schedule_repository.dart';

/// Firestore-backed [DayScheduleRepository].
///
/// Each document in the `daySchedules` collection is keyed by date
/// (YYYY-MM-DD) and stores the schedule fields directly on the document.
///
/// Firestore's built-in offline persistence (enabled by default on mobile)
/// acts as the local cache while the user is authenticated.
class CloudDayScheduleRepository implements DayScheduleRepository {
  CloudDayScheduleRepository({required FirebaseFirestore firestore})
      : _daySchedules = firestore.collection('daySchedules');

  final CollectionReference<Map<String, dynamic>> _daySchedules;

  @override
  Future<Map<String, DaySchedule>> loadAll() async {
    final snapshot = await _daySchedules.get();
    final result = <String, DaySchedule>{};
    for (final doc in snapshot.docs) {
      final data = Map<String, dynamic>.from(doc.data());
      data['date'] = doc.id;
      result[doc.id] = DaySchedule.fromJson(data);
    }
    return result;
  }

  @override
  Future<DaySchedule?> loadForDate(String date) async {
    final doc = await _daySchedules.doc(date).get();
    if (!doc.exists || doc.data() == null) return null;
    final data = Map<String, dynamic>.from(doc.data()!);
    data['date'] = date;
    return DaySchedule.fromJson(data);
  }

  @override
  Stream<Map<String, DaySchedule>> watchAll() {
    return _daySchedules.snapshots().map((snapshot) {
      final result = <String, DaySchedule>{};
      for (final doc in snapshot.docs) {
        final data = Map<String, dynamic>.from(doc.data());
        data['date'] = doc.id;
        result[doc.id] = DaySchedule.fromJson(data);
      }
      return result;
    });
  }

  @override
  Future<void> saveAll(Map<String, DaySchedule> allSchedules) async {
    final batch = _daySchedules.firestore.batch();

    final existing = await _daySchedules.get();
    for (final doc in existing.docs) {
      if (!allSchedules.containsKey(doc.id)) {
        batch.delete(doc.reference);
      }
    }

    for (final entry in allSchedules.entries) {
      batch.set(_daySchedules.doc(entry.key), entry.value.toJson());
    }

    await batch.commit();
  }
}
