import 'dart:convert';
import 'dart:io';

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

  Future<void> writeJobJson(File jobJsonFile, Map<String, dynamic> json) async {
    final parent = jobJsonFile.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final contents = jsonEncode(json);
    await atomicWriteString(jobJsonFile, contents);
  }
}
