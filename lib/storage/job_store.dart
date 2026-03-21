import 'dart:convert';
import 'dart:io';

import '../domain/models/job.dart';
import 'atomic_write.dart';

/// Reads and writes `job.json` files.
///
/// This store is intentionally narrow: it only handles JSON file I/O.
class JobStore {
  Future<Map<String, dynamic>?> readJobJson(File jobJsonFile) async {
    if (!await jobJsonFile.exists()) {
      return null;
    }

    final raw = await jobJsonFile.readAsString();

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        throw FormatException(
          'Expected a JSON object in ${jobJsonFile.path}, got ${decoded.runtimeType}.',
        );
      }
      if (decoded['notes'] is! List) {
        decoded['notes'] = <Map<String, dynamic>>[];
      }
      return decoded;
    } on FormatException catch (e) {
      throw FormatException(
        'Invalid JSON in ${jobJsonFile.path}: ${e.message}',
      );
    }
  }

  /// Reads and parses a `job.json` file into a typed [Job].
  ///
  /// Returns null if the file does not exist.
  Future<Job?> readJob(File jobJsonFile) async {
    final data = await readJobJson(jobJsonFile);
    if (data == null) return null;
    return Job.fromJson(data);
  }

  Future<void> writeJobJson(File jobJsonFile, Map<String, dynamic> json) async {
    final parent = jobJsonFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final contents = jsonEncode(json);
    await atomicWriteString(jobJsonFile, contents);
  }

  /// Writes a typed [Job] to disk, stamping [Job.updatedAt] to now (UTC).
  ///
  /// Returns the stamped [Job] so callers can keep in sync with what was written.
  Future<Job> writeJob(File jobJsonFile, Job job) async {
    final stamped = job.copyWith(
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );
    await writeJobJson(jobJsonFile, stamped.toJson());
    return stamped;
  }
}
