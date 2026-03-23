import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/cloud_day_note_repository.dart';
import '../data/repositories/cloud_day_schedule_repository.dart';
import '../data/repositories/day_note_repository.dart';
import '../data/repositories/day_schedule_repository.dart';
import '../domain/models/day_note.dart';
import '../domain/models/day_schedule.dart';
import '../domain/models/job.dart';
import '../services/auth_service.dart';
import 'web_job_repository.dart';

/// Firestore-only job repository for web.
final webJobRepositoryProvider = Provider<WebJobRepository>((ref) {
  return WebJobRepository();
});

/// Real-time stream of all jobs from Firestore.
final webJobListProvider = StreamProvider<List<Job>>((ref) {
  return ref.watch(webJobRepositoryProvider).watchAllJobs();
});

/// Day note repository — always Firestore on web.
final webDayNoteRepositoryProvider = Provider<DayNoteRepository>((ref) {
  return CloudDayNoteRepository(firestore: FirebaseFirestore.instance);
});

/// Day schedule repository — always Firestore on web.
final webDayScheduleRepositoryProvider = Provider<DayScheduleRepository>((ref) {
  return CloudDayScheduleRepository(firestore: FirebaseFirestore.instance);
});

/// All day notes, keyed by date.
final webDayNotesProvider =
    FutureProvider<Map<String, List<DayNote>>>((ref) async {
  return ref.watch(webDayNoteRepositoryProvider).loadAll();
});

/// All day schedules, keyed by date.
final webDaySchedulesProvider =
    FutureProvider<Map<String, DaySchedule>>((ref) async {
  return ref.watch(webDayScheduleRepositoryProvider).loadAll();
});

/// Firestore `users` collection for user management.
final webUsersProvider =
    StreamProvider<List<Map<String, dynamic>>>((ref) {
  return FirebaseFirestore.instance
      .collection('users')
      .snapshots()
      .map((snap) => snap.docs.map((d) {
            final data = Map<String, dynamic>.from(d.data());
            data['uid'] = d.id;
            return data;
          }).toList());
});

/// [AuthService] shared with the web auth gate.
final webAuthServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});
