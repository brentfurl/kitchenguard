import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard_photo_organizer/domain/models/day_note.dart';
import 'package:kitchenguard_photo_organizer/storage/day_note_store.dart';
import 'package:path/path.dart' as p;

void main() {
  group('DayNoteStore', () {
    late Directory tempDir;
    late File dayNotesFile;
    late DayNoteStore store;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('day_note_store_test_');
      dayNotesFile = File(p.join(tempDir.path, 'day_notes.json'));
      store = DayNoteStore.fromFile(dayNotesFile);
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    // -------------------------------------------------------------------------
    // readAll — missing / empty / malformed file
    // -------------------------------------------------------------------------

    test('readAll returns empty map when file does not exist', () async {
      expect(await store.readAll(), isEmpty);
    });

    test('readAll returns empty map for empty file', () async {
      await dayNotesFile.writeAsString('');
      expect(await store.readAll(), isEmpty);
    });

    test('readAll returns empty map for whitespace-only file', () async {
      await dayNotesFile.writeAsString('   \n  ');
      expect(await store.readAll(), isEmpty);
    });

    test('readAll returns empty map for malformed JSON', () async {
      await dayNotesFile.writeAsString('not valid json {{{');
      expect(await store.readAll(), isEmpty);
    });

    test('readAll returns empty map when JSON root is not an object', () async {
      await dayNotesFile.writeAsString('[1, 2, 3]');
      expect(await store.readAll(), isEmpty);
    });

    // -------------------------------------------------------------------------
    // write / readAll round-trip
    // -------------------------------------------------------------------------

    test('write then readAll round-trips a single note', () async {
      final note = DayNote(
        noteId: 'note-001',
        date: '2026-03-20',
        text: 'Arrive at 7 am',
        createdAt: '2026-03-20T07:00:00.000Z',
        status: 'active',
      );

      await store.write({'2026-03-20': [note]});

      final result = await store.readAll();
      expect(result.keys, contains('2026-03-20'));
      final notes = result['2026-03-20']!;
      expect(notes.length, 1);
      expect(notes.first.noteId, 'note-001');
      expect(notes.first.date, '2026-03-20');
      expect(notes.first.text, 'Arrive at 7 am');
      expect(notes.first.createdAt, '2026-03-20T07:00:00.000Z');
      expect(notes.first.status, 'active');
    });

    test('write then readAll preserves deleted status', () async {
      final note = DayNote(
        noteId: 'note-del',
        date: '2026-03-21',
        text: 'Deleted note',
        createdAt: '2026-03-21T08:00:00.000Z',
        status: 'deleted',
      );

      await store.write({'2026-03-21': [note]});

      final result = await store.readAll();
      expect(result['2026-03-21']!.first.status, 'deleted');
      expect(result['2026-03-21']!.first.isDeleted, isTrue);
      expect(result['2026-03-21']!.first.isActive, isFalse);
    });

    test('write then readAll persists multiple notes per date', () async {
      final notes = [
        DayNote(
          noteId: 'n1',
          date: '2026-03-20',
          text: 'First',
          createdAt: '2026-03-20T08:00:00.000Z',
          status: 'active',
        ),
        DayNote(
          noteId: 'n2',
          date: '2026-03-20',
          text: 'Second',
          createdAt: '2026-03-20T09:00:00.000Z',
          status: 'active',
        ),
      ];

      await store.write({'2026-03-20': notes});

      final result = await store.readAll();
      expect(result['2026-03-20']!.length, 2);
      expect(result['2026-03-20']!.map((n) => n.noteId), ['n1', 'n2']);
    });

    test('write then readAll persists notes across multiple dates', () async {
      final noteA = DayNote(
        noteId: 'a1',
        date: '2026-03-20',
        text: 'Day A note',
        createdAt: '2026-03-20T08:00:00.000Z',
        status: 'active',
      );
      final noteB = DayNote(
        noteId: 'b1',
        date: '2026-03-21',
        text: 'Day B note',
        createdAt: '2026-03-21T08:00:00.000Z',
        status: 'active',
      );

      await store.write({'2026-03-20': [noteA], '2026-03-21': [noteB]});

      final result = await store.readAll();
      expect(result.keys, containsAll(['2026-03-20', '2026-03-21']));
      expect(result['2026-03-20']!.first.noteId, 'a1');
      expect(result['2026-03-21']!.first.noteId, 'b1');
    });

    test('write creates parent directories if needed', () async {
      final nestedFile = File(
        p.join(tempDir.path, 'subdir', 'day_notes.json'),
      );
      final nestedStore = DayNoteStore.fromFile(nestedFile);

      final note = DayNote(
        noteId: 'nested-1',
        date: '2026-03-20',
        text: 'Nested',
        createdAt: '2026-03-20T10:00:00.000Z',
        status: 'active',
      );

      await nestedStore.write({'2026-03-20': [note]});

      expect(await nestedFile.exists(), isTrue);
      final result = await nestedStore.readAll();
      expect(result['2026-03-20']!.first.noteId, 'nested-1');
    });

    test('written file contains valid JSON', () async {
      final note = DayNote(
        noteId: 'json-check',
        date: '2026-03-20',
        text: 'Check file',
        createdAt: '2026-03-20T10:00:00.000Z',
        status: 'active',
      );

      await store.write({'2026-03-20': [note]});

      final raw = await dayNotesFile.readAsString();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      expect(decoded.containsKey('2026-03-20'), isTrue);
    });

    test('write overwrites previous contents', () async {
      final note1 = DayNote(
        noteId: 'old',
        date: '2026-03-20',
        text: 'Old note',
        createdAt: '2026-03-20T08:00:00.000Z',
        status: 'active',
      );
      await store.write({'2026-03-20': [note1]});

      final note2 = DayNote(
        noteId: 'new',
        date: '2026-03-22',
        text: 'New note',
        createdAt: '2026-03-22T08:00:00.000Z',
        status: 'active',
      );
      await store.write({'2026-03-22': [note2]});

      final result = await store.readAll();
      expect(result.keys, isNot(contains('2026-03-20')));
      expect(result.keys, contains('2026-03-22'));
    });

    // -------------------------------------------------------------------------
    // readForDate
    // -------------------------------------------------------------------------

    test('readForDate returns notes for the given date', () async {
      final note = DayNote(
        noteId: 'rfd-1',
        date: '2026-03-20',
        text: 'Shift start',
        createdAt: '2026-03-20T07:30:00.000Z',
        status: 'active',
      );
      await store.write({'2026-03-20': [note]});

      final notes = await store.readForDate('2026-03-20');
      expect(notes.length, 1);
      expect(notes.first.noteId, 'rfd-1');
    });

    test('readForDate returns empty list for a date with no notes', () async {
      final note = DayNote(
        noteId: 'rfd-2',
        date: '2026-03-20',
        text: 'Some note',
        createdAt: '2026-03-20T07:30:00.000Z',
        status: 'active',
      );
      await store.write({'2026-03-20': [note]});

      final notes = await store.readForDate('2026-03-21');
      expect(notes, isEmpty);
    });

    test('readForDate returns empty list when file does not exist', () async {
      final notes = await store.readForDate('2026-03-20');
      expect(notes, isEmpty);
    });

    // -------------------------------------------------------------------------
    // graceful handling of partial data
    // -------------------------------------------------------------------------

    test('readAll skips entries where value is not a list', () async {
      await dayNotesFile.writeAsString(
        jsonEncode({'2026-03-20': 'not a list', '2026-03-21': []}),
      );

      final result = await store.readAll();
      expect(result.containsKey('2026-03-20'), isFalse);
      expect(result.containsKey('2026-03-21'), isTrue);
      expect(result['2026-03-21'], isEmpty);
    });

    test('readAll skips non-map entries inside a date array', () async {
      await dayNotesFile.writeAsString(
        jsonEncode({
          '2026-03-20': [
            {
              'noteId': 'valid',
              'date': '2026-03-20',
              'text': 'valid note',
              'createdAt': '2026-03-20T08:00:00.000Z',
              'status': 'active',
            },
            'not a map',
            42,
          ],
        }),
      );

      final result = await store.readAll();
      expect(result['2026-03-20']!.length, 1);
      expect(result['2026-03-20']!.first.noteId, 'valid');
    });
  });
}
