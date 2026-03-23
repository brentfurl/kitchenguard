import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard_photo_organizer/application/jobs_service.dart';
import 'package:kitchenguard_photo_organizer/data/repositories/local_day_note_repository.dart';
import 'package:kitchenguard_photo_organizer/data/repositories/local_job_repository.dart';
import 'package:kitchenguard_photo_organizer/domain/models/job.dart';
import 'package:kitchenguard_photo_organizer/domain/models/videos.dart';
import 'package:kitchenguard_photo_organizer/storage/app_paths.dart';
import 'package:kitchenguard_photo_organizer/storage/atomic_write.dart';
import 'package:kitchenguard_photo_organizer/storage/day_note_store.dart';
import 'package:kitchenguard_photo_organizer/storage/image_file_store.dart';
import 'package:kitchenguard_photo_organizer/storage/job_scanner.dart';
import 'package:kitchenguard_photo_organizer/storage/job_store.dart';
import 'package:kitchenguard_photo_organizer/storage/video_file_store.dart';
import 'package:path/path.dart' as p;

void main() {
  group('JobsService scheduling', () {
    late Directory tempDir;
    late Directory jobDir;
    late File jobJsonFile;
    late JobStore jobStore;
    late DayNoteStore dayNoteStore;
    late JobsService service;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp(
        'jobs_service_scheduling_test_',
      );
      jobDir = Directory(p.join(tempDir.path, 'TestRestaurant_2026-03-20'));
      await jobDir.create(recursive: true);
      jobJsonFile = File(p.join(jobDir.path, 'job.json'));

      jobStore = JobStore();
      final dayNotesFile = File(p.join(tempDir.path, 'day_notes.json'));
      dayNoteStore = DayNoteStore.fromFile(dayNotesFile);

      final paths = AppPaths();
      final imageStore = ImageFileStore(paths: paths);
      final videoStore =
          VideoFileStore(paths: paths, atomicWrite: atomicWriteBytes);
      final jobScanner = JobScanner(paths: paths, jobStore: jobStore);

      service = JobsService(
        paths: paths,
        jobRepository: LocalJobRepository(
          paths: paths,
          jobStore: jobStore,
          jobScanner: jobScanner,
          imageStore: imageStore,
          videoStore: videoStore,
        ),
        dayNoteRepository: LocalDayNoteRepository(
          dayNoteStore: dayNoteStore,
        ),
      );

      final job = Job(
        jobId: 'test-job-id',
        restaurantName: 'Test Restaurant',
        shiftStartDate: '2026-03-20',
        createdAt: '2026-03-20T08:00:00.000Z',
        schemaVersion: 2,
        units: const [],
        notes: const [],
        preCleanLayoutPhotos: const [],
        videos: const Videos.empty(),
      );
      await jobStore.writeJob(jobJsonFile, job);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    // -------------------------------------------------------------------------
    // setScheduledDate
    // -------------------------------------------------------------------------

    group('setScheduledDate', () {
      test('sets a scheduled date and returns updated Job', () async {
        final updated = await service.setScheduledDate(jobDir, '2026-03-25');

        expect(updated.scheduledDate, '2026-03-25');
        expect(updated.jobId, 'test-job-id');
      });

      test('persists the scheduled date to job.json', () async {
        await service.setScheduledDate(jobDir, '2026-03-25');

        final reloaded = await jobStore.readJob(jobJsonFile);
        expect(reloaded!.scheduledDate, '2026-03-25');
      });

      test('stamps updatedAt on write', () async {
        final before = DateTime.now().toUtc();
        final updated = await service.setScheduledDate(jobDir, '2026-03-25');
        final after = DateTime.now().toUtc();

        final updatedAt = DateTime.parse(updated.updatedAt!);
        expect(
          updatedAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue,
        );
        expect(
          updatedAt.isBefore(after.add(const Duration(seconds: 1))),
          isTrue,
        );
      });

      test('clears scheduled date when null is passed', () async {
        await service.setScheduledDate(jobDir, '2026-03-25');

        final cleared = await service.setScheduledDate(jobDir, null);
        expect(cleared.scheduledDate, isNull);
      });

      test('persists cleared (null) scheduled date', () async {
        await service.setScheduledDate(jobDir, '2026-03-25');
        await service.setScheduledDate(jobDir, null);

        final reloaded = await jobStore.readJob(jobJsonFile);
        expect(reloaded!.scheduledDate, isNull);
      });

      test('preserves other fields when setting scheduled date', () async {
        await service.setSortOrder(jobDir, 3);
        final updated = await service.setScheduledDate(jobDir, '2026-03-25');

        expect(updated.sortOrder, 3);
        expect(updated.restaurantName, 'Test Restaurant');
      });

      test('throws StateError when job.json is missing', () async {
        await jobJsonFile.delete();
        expect(
          () => service.setScheduledDate(jobDir, '2026-03-25'),
          throwsStateError,
        );
      });
    });

    // -------------------------------------------------------------------------
    // setSortOrder
    // -------------------------------------------------------------------------

    group('setSortOrder', () {
      test('sets sort order and returns updated Job', () async {
        final updated = await service.setSortOrder(jobDir, 2);

        expect(updated.sortOrder, 2);
        expect(updated.jobId, 'test-job-id');
      });

      test('persists sort order to job.json', () async {
        await service.setSortOrder(jobDir, 2);

        final reloaded = await jobStore.readJob(jobJsonFile);
        expect(reloaded!.sortOrder, 2);
      });

      test('stamps updatedAt on write', () async {
        final before = DateTime.now().toUtc();
        final updated = await service.setSortOrder(jobDir, 1);
        final after = DateTime.now().toUtc();

        final updatedAt = DateTime.parse(updated.updatedAt!);
        expect(
          updatedAt.isAfter(before.subtract(const Duration(seconds: 1))),
          isTrue,
        );
        expect(
          updatedAt.isBefore(after.add(const Duration(seconds: 1))),
          isTrue,
        );
      });

      test('clears sort order when null is passed', () async {
        await service.setSortOrder(jobDir, 2);

        final cleared = await service.setSortOrder(jobDir, null);
        expect(cleared.sortOrder, isNull);
      });

      test('persists cleared (null) sort order', () async {
        await service.setSortOrder(jobDir, 2);
        await service.setSortOrder(jobDir, null);

        final reloaded = await jobStore.readJob(jobJsonFile);
        expect(reloaded!.sortOrder, isNull);
      });

      test('preserves other fields when setting sort order', () async {
        await service.setScheduledDate(jobDir, '2026-03-25');
        final updated = await service.setSortOrder(jobDir, 1);

        expect(updated.scheduledDate, '2026-03-25');
        expect(updated.restaurantName, 'Test Restaurant');
      });

      test('throws StateError when job.json is missing', () async {
        await jobJsonFile.delete();
        expect(
          () => service.setSortOrder(jobDir, 1),
          throwsStateError,
        );
      });
    });

    // -------------------------------------------------------------------------
    // addDayNote
    // -------------------------------------------------------------------------

    group('addDayNote', () {
      test('creates a DayNote and returns it', () async {
        final note = await service.addDayNote('2026-03-20', 'Arrive at 8am');

        expect(note.noteId, isNotEmpty);
        expect(note.date, '2026-03-20');
        expect(note.text, 'Arrive at 8am');
        expect(note.status, 'active');
        expect(note.isActive, isTrue);
        expect(note.createdAt, isNotEmpty);
      });

      test('assigns a unique noteId each call', () async {
        final n1 = await service.addDayNote('2026-03-20', 'Note one');
        final n2 = await service.addDayNote('2026-03-20', 'Note two');

        expect(n1.noteId, isNot(equals(n2.noteId)));
      });

      test('persists the note — loadDayNotes returns it', () async {
        await service.addDayNote('2026-03-20', 'Crew: 3 people');

        final loaded = await service.loadDayNotes('2026-03-20');
        expect(loaded.length, 1);
        expect(loaded.first.text, 'Crew: 3 people');
      });

      test('trims whitespace from text', () async {
        final note = await service.addDayNote('2026-03-20', '  trimmed  ');

        expect(note.text, 'trimmed');
      });

      test('throws ArgumentError for empty text', () async {
        await expectLater(
          () => service.addDayNote('2026-03-20', ''),
          throwsArgumentError,
        );
      });

      test('throws ArgumentError for whitespace-only text', () async {
        await expectLater(
          () => service.addDayNote('2026-03-20', '   '),
          throwsArgumentError,
        );
      });

      test('appends notes to the same date', () async {
        await service.addDayNote('2026-03-20', 'First note');
        await service.addDayNote('2026-03-20', 'Second note');

        final loaded = await service.loadDayNotes('2026-03-20');
        expect(loaded.length, 2);
        expect(loaded.map((n) => n.text), ['First note', 'Second note']);
      });

      test('notes for different dates are independent', () async {
        await service.addDayNote('2026-03-20', 'Day 1');
        await service.addDayNote('2026-03-21', 'Day 2');

        final day1 = await service.loadDayNotes('2026-03-20');
        final day2 = await service.loadDayNotes('2026-03-21');

        expect(day1.length, 1);
        expect(day1.first.text, 'Day 1');
        expect(day2.length, 1);
        expect(day2.first.text, 'Day 2');
      });
    });

    // -------------------------------------------------------------------------
    // softDeleteDayNote
    // -------------------------------------------------------------------------

    group('softDeleteDayNote', () {
      test('marks note as deleted — excluded from loadDayNotes', () async {
        final note = await service.addDayNote('2026-03-20', 'To be deleted');
        await service.softDeleteDayNote('2026-03-20', note.noteId);

        final active = await service.loadDayNotes('2026-03-20');
        expect(active, isEmpty);
      });

      test('only deletes the targeted note, leaving others active', () async {
        final keep = await service.addDayNote('2026-03-20', 'Keep this');
        final del = await service.addDayNote('2026-03-20', 'Delete this');
        await service.softDeleteDayNote('2026-03-20', del.noteId);

        final active = await service.loadDayNotes('2026-03-20');
        expect(active.length, 1);
        expect(active.first.noteId, keep.noteId);
      });

      test('deleted note is still present in raw store data', () async {
        final note = await service.addDayNote('2026-03-20', 'Soft delete me');
        await service.softDeleteDayNote('2026-03-20', note.noteId);

        final all = await service.loadAllDayNotes();
        final notesForDate = all['2026-03-20']!;
        expect(notesForDate.length, 1);
        expect(notesForDate.first.status, 'deleted');
        expect(notesForDate.first.isDeleted, isTrue);
      });

      test('throws StateError when noteId not found', () async {
        await expectLater(
          () => service.softDeleteDayNote('2026-03-20', 'nonexistent-id'),
          throwsStateError,
        );
      });

      test('throws StateError when date has no notes', () async {
        await expectLater(
          () => service.softDeleteDayNote('2026-03-20', 'any-id'),
          throwsStateError,
        );
      });
    });

    // -------------------------------------------------------------------------
    // loadDayNotes
    // -------------------------------------------------------------------------

    group('loadDayNotes', () {
      test('returns only active notes for the date', () async {
        final active = await service.addDayNote('2026-03-20', 'Active');
        final deleted = await service.addDayNote('2026-03-20', 'Deleted');
        await service.softDeleteDayNote('2026-03-20', deleted.noteId);

        final notes = await service.loadDayNotes('2026-03-20');
        expect(notes.length, 1);
        expect(notes.first.noteId, active.noteId);
      });

      test('returns empty list when no notes exist for date', () async {
        final notes = await service.loadDayNotes('2026-03-99');
        expect(notes, isEmpty);
      });

      test('returns empty list after all notes for a date are deleted',
          () async {
        final note = await service.addDayNote('2026-03-20', 'Only note');
        await service.softDeleteDayNote('2026-03-20', note.noteId);

        final notes = await service.loadDayNotes('2026-03-20');
        expect(notes, isEmpty);
      });
    });

    // -------------------------------------------------------------------------
    // loadAllDayNotes
    // -------------------------------------------------------------------------

    group('loadAllDayNotes', () {
      test('returns empty map when no notes have been added', () async {
        final all = await service.loadAllDayNotes();
        expect(all, isEmpty);
      });

      test('returns notes across multiple dates', () async {
        await service.addDayNote('2026-03-20', 'Day 1 note');
        await service.addDayNote('2026-03-21', 'Day 2 note');

        final all = await service.loadAllDayNotes();
        expect(all.keys, containsAll(['2026-03-20', '2026-03-21']));
      });

      test('includes deleted notes in the full map', () async {
        final note = await service.addDayNote('2026-03-20', 'Will be deleted');
        await service.softDeleteDayNote('2026-03-20', note.noteId);

        final all = await service.loadAllDayNotes();
        final notes = all['2026-03-20']!;
        expect(notes.length, 1);
        expect(notes.first.isDeleted, isTrue);
      });

      test('reflects additions made after initial load', () async {
        await service.addDayNote('2026-03-20', 'First');
        final map1 = await service.loadAllDayNotes();
        expect(map1['2026-03-20']!.length, 1);

        await service.addDayNote('2026-03-20', 'Second');
        final map2 = await service.loadAllDayNotes();
        expect(map2['2026-03-20']!.length, 2);
      });
    });
  });
}
