import 'dart:developer' as developer;
import 'dart:math' as math;

import '../models/job.dart';
import '../models/job_note.dart';
import '../models/manager_job_note.dart';
import '../models/photo_record.dart';
import '../models/unit.dart';
import '../models/video_record.dart';
import '../models/videos.dart';

/// Pure-function merge logic for combining a local [Job] with a cloud [Job].
///
/// **Strategy:**
/// - Scheduling / metadata fields: last-write-wins via [Job.updatedAt].
/// - Documentation data (photos, videos, notes): append-only union by ID.
/// - Note text content: last-write-wins via [JobNote.updatedAt] /
///   [ManagerJobNote.updatedAt] when the same noteId exists on both sides.
/// - Soft-deletion is additive: if either side is deleted, the merge result
///   is deleted.
/// - Sync metadata (syncStatus, cloudUrl, uploadedBy) prefers the "better"
///   status (synced > uploading > error > pending > null).
class JobMerger {
  const JobMerger._();

  /// Merges [local] and [cloud] into a single [Job].
  ///
  /// Local is the base for filesystem-owned fields (relativePath, fileName,
  /// missingLocal, etc.). Cloud contributes sync metadata and any records
  /// captured by other devices.
  static Job merge({required Job local, required Job cloud}) {
    final localUpdated = DateTime.tryParse(local.updatedAt ?? '');
    final cloudUpdated = DateTime.tryParse(cloud.updatedAt ?? '');
    final cloudIsNewer = _isAfter(cloudUpdated, localUpdated);

    developer.log(
      'Merging ${local.restaurantName}: '
      'local ${local.units.length} units / ${local.preCleanLayoutPhotos.length} preclean, '
      'cloud ${cloud.units.length} units / ${cloud.preCleanLayoutPhotos.length} preclean, '
      'sched winner=${cloudIsNewer ? "cloud" : "local"}',
      name: 'JobMerger',
    );

    final sched = cloudIsNewer ? cloud : local;

    return Job(
      jobId: local.jobId,
      shiftStartDate: local.shiftStartDate,
      createdAt: local.createdAt,
      updatedAt: cloudIsNewer ? cloud.updatedAt : local.updatedAt,
      schemaVersion: math.max(local.schemaVersion, cloud.schemaVersion),
      restaurantName: sched.restaurantName,
      scheduledDate: sched.scheduledDate,
      sortOrder: sched.sortOrder,
      completedAt: sched.completedAt,
      address: sched.address,
      city: sched.city,
      accessType: sched.accessType,
      accessNotes: sched.accessNotes,
      hasAlarm: sched.hasAlarm,
      alarmCode: sched.alarmCode,
      hoodCount: sched.hoodCount,
      fanCount: sched.fanCount,
      clientId: sched.clientId,
      units: _mergeUnits(local.units, cloud.units),
      notes: _mergeJobNotes(local.notes, cloud.notes),
      managerNotes: _mergeManagerNotes(local.managerNotes, cloud.managerNotes),
      preCleanLayoutPhotos:
          _mergePhotos(local.preCleanLayoutPhotos, cloud.preCleanLayoutPhotos),
      videos: _mergeVideos(local.videos, cloud.videos),
    );
  }

  // ---------------------------------------------------------------------------
  // Units
  // ---------------------------------------------------------------------------

  static List<Unit> _mergeUnits(List<Unit> local, List<Unit> cloud) {
    final cloudMap = <String, Unit>{};
    for (final u in cloud) {
      if (u.unitId.isNotEmpty) cloudMap[u.unitId] = u;
    }

    final seenIds = <String>{};
    final merged = <Unit>[];

    for (final lu in local) {
      seenIds.add(lu.unitId);
      final cu = cloudMap[lu.unitId];
      if (cu != null) {
        final mergedBefore = _mergePhotos(lu.photosBefore, cu.photosBefore);
        final mergedAfter = _mergePhotos(lu.photosAfter, cu.photosAfter);
        final newBefore = mergedBefore.length - lu.photosBefore.length;
        final newAfter = mergedAfter.length - lu.photosAfter.length;
        if (newBefore > 0 || newAfter > 0) {
          developer.log(
            'Unit ${lu.name}: +$newBefore before, +$newAfter after photos from cloud',
            name: 'JobMerger',
          );
        }
        merged.add(lu.copyWith(
          photosBefore: mergedBefore,
          photosAfter: mergedAfter,
        ));
      } else {
        merged.add(lu);
      }
    }

    for (final cu in cloud) {
      if (cu.unitId.isNotEmpty && !seenIds.contains(cu.unitId)) {
        developer.log(
          'Appending cloud-only unit: ${cu.name} (${cu.type}, '
          '${cu.photosBefore.length}B/${cu.photosAfter.length}A photos)',
          name: 'JobMerger',
        );
        merged.add(cu);
      }
    }

    return _resolveDuplicateUnitNames(merged);
  }

  static List<Unit> _resolveDuplicateUnitNames(List<Unit> units) {
    if (units.length < 2) return units;

    final indexed = <_IndexedUnit>[];
    for (var i = 0; i < units.length; i++) {
      indexed.add(_IndexedUnit(index: i, unit: units[i]));
    }

    final byType = <String, List<_IndexedUnit>>{};
    for (final item in indexed) {
      final typeKey = item.unit.type.trim().toLowerCase();
      byType.putIfAbsent(typeKey, () => []).add(item);
    }

    var renamedCount = 0;
    final updated = [...units];

    for (final entry in byType.entries) {
      final typeKey = entry.key;
      final entries = [...entry.value]
        ..sort((a, b) => a.unit.unitId.compareTo(b.unit.unitId));

      final usedNames = <String>{};
      var nextNumeric = _nextNumericUnitIndex(entries.map((e) => e.unit.name), typeKey);

      for (final item in entries) {
        final currentName = item.unit.name.trim();
        final normalized = _normalizeUnitName(currentName);

        if (normalized.isNotEmpty && !usedNames.contains(normalized)) {
          usedNames.add(normalized);
          continue;
        }

        final fallbackBase = currentName.isNotEmpty ? currentName : typeKey;
        final generated = _generateUniqueUnitName(
          typeKey: typeKey,
          fallbackBase: fallbackBase,
          usedNormalizedNames: usedNames,
          nextNumericHint: nextNumeric,
        );
        if (generated.nextNumericHint > nextNumeric) {
          nextNumeric = generated.nextNumericHint;
        }

        updated[item.index] = item.unit.copyWith(name: generated.name);
        usedNames.add(_normalizeUnitName(generated.name));
        renamedCount += 1;
      }
    }

    if (renamedCount > 0) {
      developer.log(
        'Resolved $renamedCount duplicate unit name(s) from concurrent edits',
        name: 'JobMerger',
      );
    }

    return updated;
  }

  // ---------------------------------------------------------------------------
  // Photos
  // ---------------------------------------------------------------------------

  static List<PhotoRecord> _mergePhotos(
    List<PhotoRecord> local,
    List<PhotoRecord> cloud,
  ) {
    final cloudMap = <String, PhotoRecord>{};
    for (final p in cloud) {
      if (p.photoId.isNotEmpty) cloudMap[p.photoId] = p;
    }

    final seenIds = <String>{};
    final merged = <PhotoRecord>[];

    for (final lp in local) {
      seenIds.add(lp.photoId);
      final cp = cloudMap[lp.photoId];
      merged.add(cp != null ? _mergePhotoRecord(lp, cp) : lp);
    }

    var cloudOnlyCount = 0;
    for (final cp in cloud) {
      if (cp.photoId.isNotEmpty && !seenIds.contains(cp.photoId)) {
        merged.add(cp);
        cloudOnlyCount++;
      }
    }
    if (cloudOnlyCount > 0) {
      developer.log(
        'Appended $cloudOnlyCount cloud-only photo(s) '
        '(with cloudUrl: '
        '${cloud.where((p) => !seenIds.contains(p.photoId) && p.cloudUrl != null).length})',
        name: 'JobMerger',
      );
    }

    return merged;
  }

  static PhotoRecord _mergePhotoRecord(PhotoRecord local, PhotoRecord cloud) {
    final syncStatus = _betterSyncStatus(local.syncStatus, cloud.syncStatus);
    final syncSource = syncStatus == cloud.syncStatus ? cloud : local;
    final cloudDeletedLocal = cloud.isDeleted && !local.isDeleted;

    if (cloudDeletedLocal) {
      return local.copyWith(
        status: 'deleted',
        deletedAt: cloud.deletedAt,
        syncStatus: syncStatus,
        cloudUrl: syncSource.cloudUrl,
        uploadedBy: syncSource.uploadedBy,
      );
    }

    if (syncStatus != local.syncStatus) {
      return local.copyWith(
        syncStatus: syncStatus,
        cloudUrl: syncSource.cloudUrl,
        uploadedBy: syncSource.uploadedBy,
      );
    }

    return local;
  }

  // ---------------------------------------------------------------------------
  // Videos
  // ---------------------------------------------------------------------------

  static Videos _mergeVideos(Videos local, Videos cloud) {
    return Videos(
      exit: _mergeVideoRecords(local.exit, cloud.exit),
      other: _mergeVideoRecords(local.other, cloud.other),
    );
  }

  static List<VideoRecord> _mergeVideoRecords(
    List<VideoRecord> local,
    List<VideoRecord> cloud,
  ) {
    final cloudMap = <String, VideoRecord>{};
    for (final v in cloud) {
      if (v.videoId.isNotEmpty) cloudMap[v.videoId] = v;
    }

    final seenIds = <String>{};
    final merged = <VideoRecord>[];

    for (final lv in local) {
      seenIds.add(lv.videoId);
      final cv = cloudMap[lv.videoId];
      merged.add(cv != null ? _mergeVideoRecord(lv, cv) : lv);
    }

    for (final cv in cloud) {
      if (cv.videoId.isNotEmpty && !seenIds.contains(cv.videoId)) {
        merged.add(cv);
      }
    }

    return merged;
  }

  static VideoRecord _mergeVideoRecord(VideoRecord local, VideoRecord cloud) {
    final syncStatus = _betterSyncStatus(local.syncStatus, cloud.syncStatus);
    final syncSource = syncStatus == cloud.syncStatus ? cloud : local;
    final cloudDeletedLocal = cloud.isDeleted && !local.isDeleted;

    if (cloudDeletedLocal) {
      return local.copyWith(
        status: 'deleted',
        deletedAt: cloud.deletedAt,
        syncStatus: syncStatus,
        cloudUrl: syncSource.cloudUrl,
        uploadedBy: syncSource.uploadedBy,
      );
    }

    if (syncStatus != local.syncStatus) {
      return local.copyWith(
        syncStatus: syncStatus,
        cloudUrl: syncSource.cloudUrl,
        uploadedBy: syncSource.uploadedBy,
      );
    }

    return local;
  }

  // ---------------------------------------------------------------------------
  // Notes
  // ---------------------------------------------------------------------------

  static List<JobNote> _mergeJobNotes(
    List<JobNote> local,
    List<JobNote> cloud,
  ) {
    final cloudMap = <String, JobNote>{};
    for (final n in cloud) {
      if (n.noteId.isNotEmpty) cloudMap[n.noteId] = n;
    }

    final seenIds = <String>{};
    final merged = <JobNote>[];

    for (final ln in local) {
      seenIds.add(ln.noteId);
      final cn = cloudMap[ln.noteId];
      if (cn == null) {
        merged.add(ln);
      } else if (cn.isDeleted && !ln.isDeleted) {
        merged.add(ln.copyWith(status: 'deleted'));
      } else if (_isAfter(
        DateTime.tryParse(cn.updatedAt ?? ''),
        DateTime.tryParse(ln.updatedAt ?? ''),
      )) {
        merged.add(ln.copyWith(text: cn.text, updatedAt: cn.updatedAt));
      } else {
        merged.add(ln);
      }
    }

    for (final cn in cloud) {
      if (cn.noteId.isNotEmpty && !seenIds.contains(cn.noteId)) {
        merged.add(cn);
      }
    }

    return merged;
  }

  static List<ManagerJobNote> _mergeManagerNotes(
    List<ManagerJobNote> local,
    List<ManagerJobNote> cloud,
  ) {
    final cloudMap = <String, ManagerJobNote>{};
    for (final n in cloud) {
      if (n.noteId.isNotEmpty) cloudMap[n.noteId] = n;
    }

    final seenIds = <String>{};
    final merged = <ManagerJobNote>[];

    for (final ln in local) {
      seenIds.add(ln.noteId);
      final cn = cloudMap[ln.noteId];
      if (cn == null) {
        merged.add(ln);
      } else if (cn.isDeleted && !ln.isDeleted) {
        merged.add(ln.copyWith(status: 'deleted'));
      } else if (_isAfter(
        DateTime.tryParse(cn.updatedAt ?? ''),
        DateTime.tryParse(ln.updatedAt ?? ''),
      )) {
        merged.add(ln.copyWith(text: cn.text, updatedAt: cn.updatedAt));
      } else {
        merged.add(ln);
      }
    }

    for (final cn in cloud) {
      if (cn.noteId.isNotEmpty && !seenIds.contains(cn.noteId)) {
        merged.add(cn);
      }
    }

    return merged;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns `true` if [a] is strictly after [b], treating null as epoch.
  static bool _isAfter(DateTime? a, DateTime? b) {
    if (a == null) return false;
    if (b == null) return true;
    return a.isAfter(b);
  }

  /// Returns whichever sync status ranks higher.
  ///
  /// Ranking: synced (4) > uploading (3) > error (2) > pending (1) > null (0).
  static String? _betterSyncStatus(String? a, String? b) {
    const rank = {'synced': 4, 'uploading': 3, 'error': 2, 'pending': 1};
    final ra = rank[a] ?? 0;
    final rb = rank[b] ?? 0;
    return ra >= rb ? a : b;
  }

  static String _normalizeUnitName(String name) {
    return name.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  static int _nextNumericUnitIndex(Iterable<String> names, String typeKey) {
    if (typeKey != 'hood' && typeKey != 'fan') return 1;
    final pattern = RegExp('^${RegExp.escape(typeKey)}\\s*(\\d+)\$', caseSensitive: false);
    var maxValue = 0;
    for (final raw in names) {
      final match = pattern.firstMatch(raw.trim());
      final value = match == null ? null : int.tryParse(match.group(1)!);
      if (value != null && value > maxValue) {
        maxValue = value;
      }
    }
    return maxValue + 1;
  }

  static _GeneratedUnitName _generateUniqueUnitName({
    required String typeKey,
    required String fallbackBase,
    required Set<String> usedNormalizedNames,
    required int nextNumericHint,
  }) {
    if (typeKey == 'hood' || typeKey == 'fan') {
      var index = nextNumericHint <= 0 ? 1 : nextNumericHint;
      while (usedNormalizedNames.contains(_normalizeUnitName('$typeKey $index'))) {
        index += 1;
      }
      return _GeneratedUnitName(name: '$typeKey $index', nextNumericHint: index + 1);
    }

    final base = fallbackBase.trim().isEmpty ? 'unit' : fallbackBase.trim();
    var suffix = 2;
    var candidate = '$base ($suffix)';
    while (usedNormalizedNames.contains(_normalizeUnitName(candidate))) {
      suffix += 1;
      candidate = '$base ($suffix)';
    }
    return _GeneratedUnitName(name: candidate, nextNumericHint: nextNumericHint);
  }
}

class _IndexedUnit {
  const _IndexedUnit({
    required this.index,
    required this.unit,
  });

  final int index;
  final Unit unit;
}

class _GeneratedUnitName {
  const _GeneratedUnitName({
    required this.name,
    required this.nextNumericHint,
  });

  final String name;
  final int nextNumericHint;
}
