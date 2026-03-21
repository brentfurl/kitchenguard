import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../domain/models/day_note.dart';
import 'app_paths.dart';
import 'atomic_write.dart';

/// Reads and writes `day_notes.json` in the root KitchenCleaningJobs/ directory.
///
/// File format: `{ "YYYY-MM-DD": [ {DayNote json}, ... ] }`
class DayNoteStore {
  DayNoteStore({required AppPaths paths})
      : _fileResolver = (() async {
          final root = await paths.getRootPath();
          return File(p.join(root, 'day_notes.json'));
        });

  /// Constructor for tests — bypasses path_provider by accepting a [File] directly.
  DayNoteStore.fromFile(File file) : _fileResolver = (() async => file);

  final Future<File> Function() _fileResolver;

  /// Reads all day notes from disk.
  ///
  /// Returns an empty map if the file is missing, empty, or malformed.
  Future<Map<String, List<DayNote>>> readAll() async {
    final file = await _fileResolver();

    if (!await file.exists()) return {};

    final raw = await file.readAsString();
    if (raw.trim().isEmpty) return {};

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return {};

      final result = <String, List<DayNote>>{};
      for (final entry in decoded.entries) {
        final list = entry.value;
        if (list is! List) continue;
        result[entry.key] = list
            .whereType<Map<String, dynamic>>()
            .map(DayNote.fromJson)
            .toList();
      }
      return result;
    } on FormatException {
      return {};
    }
  }

  /// Returns all notes for [date], or an empty list if none exist.
  Future<List<DayNote>> readForDate(String date) async {
    final all = await readAll();
    return all[date] ?? [];
  }

  /// Writes the full [allNotes] map to disk atomically.
  Future<void> write(Map<String, List<DayNote>> allNotes) async {
    final file = await _fileResolver();
    final json = <String, dynamic>{
      for (final entry in allNotes.entries)
        entry.key: entry.value.map((n) => n.toJson()).toList(),
    };
    await atomicWriteString(file, jsonEncode(json));
  }
}
