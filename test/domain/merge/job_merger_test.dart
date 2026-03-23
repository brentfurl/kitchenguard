import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard_photo_organizer/domain/merge/job_merger.dart';
import 'package:kitchenguard_photo_organizer/domain/models/job.dart';
import 'package:kitchenguard_photo_organizer/domain/models/job_note.dart';
import 'package:kitchenguard_photo_organizer/domain/models/manager_job_note.dart';
import 'package:kitchenguard_photo_organizer/domain/models/photo_record.dart';
import 'package:kitchenguard_photo_organizer/domain/models/unit.dart';
import 'package:kitchenguard_photo_organizer/domain/models/video_record.dart';
import 'package:kitchenguard_photo_organizer/domain/models/videos.dart';

// ---------------------------------------------------------------------------
// Test helpers
// ---------------------------------------------------------------------------

Job _baseJob({
  String jobId = 'job-1',
  String restaurantName = 'Test Restaurant',
  String? updatedAt,
  List<Unit>? units,
  List<JobNote>? notes,
  List<ManagerJobNote>? managerNotes,
  List<PhotoRecord>? preCleanLayoutPhotos,
  Videos? videos,
  String? scheduledDate,
  int? sortOrder,
  String? completedAt,
  String? address,
  String? city,
  String? clientId,
  int schemaVersion = 1,
}) {
  return Job(
    jobId: jobId,
    restaurantName: restaurantName,
    shiftStartDate: '2025-01-01',
    createdAt: '2025-01-01T00:00:00Z',
    updatedAt: updatedAt,
    schemaVersion: schemaVersion,
    scheduledDate: scheduledDate,
    sortOrder: sortOrder,
    completedAt: completedAt,
    address: address,
    city: city,
    clientId: clientId,
    units: units ?? const [],
    notes: notes ?? const [],
    managerNotes: managerNotes ?? const [],
    preCleanLayoutPhotos: preCleanLayoutPhotos ?? const [],
    videos: videos ?? const Videos.empty(),
  );
}

PhotoRecord _photo({
  required String id,
  String status = 'local',
  String? syncStatus,
  String? cloudUrl,
  String? uploadedBy,
  String? deletedAt,
  String? subPhase,
}) {
  return PhotoRecord(
    photoId: id,
    fileName: '$id.jpg',
    relativePath: 'photos/$id.jpg',
    capturedAt: '2025-01-01T12:00:00Z',
    status: status,
    missingLocal: false,
    recovered: false,
    syncStatus: syncStatus,
    cloudUrl: cloudUrl,
    uploadedBy: uploadedBy,
    deletedAt: deletedAt,
    subPhase: subPhase,
  );
}

VideoRecord _video({
  required String id,
  String status = 'local',
  String? syncStatus,
  String? cloudUrl,
  String? uploadedBy,
  String? deletedAt,
}) {
  return VideoRecord(
    videoId: id,
    fileName: '$id.mp4',
    relativePath: 'videos/$id.mp4',
    capturedAt: '2025-01-01T12:00:00Z',
    status: status,
    syncStatus: syncStatus,
    cloudUrl: cloudUrl,
    uploadedBy: uploadedBy,
    deletedAt: deletedAt,
  );
}

Unit _unit({
  required String id,
  String type = 'hood',
  List<PhotoRecord>? before,
  List<PhotoRecord>? after,
}) {
  return Unit(
    unitId: id,
    type: type,
    name: 'Hood 1',
    unitFolderName: 'hood_1',
    isComplete: false,
    photosBefore: before ?? const [],
    photosAfter: after ?? const [],
  );
}

JobNote _note({
  required String id,
  String text = 'note text',
  String status = 'active',
}) {
  return JobNote(
    noteId: id,
    text: text,
    createdAt: '2025-01-01T12:00:00Z',
    status: status,
  );
}

ManagerJobNote _mgrNote({
  required String id,
  String text = 'manager note',
  String status = 'active',
}) {
  return ManagerJobNote(
    noteId: id,
    text: text,
    createdAt: '2025-01-01T12:00:00Z',
    status: status,
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  group('JobMerger — scheduling fields (last-write-wins)', () {
    test('cloud-newer wins scheduling fields', () {
      final local = _baseJob(
        restaurantName: 'Local Name',
        updatedAt: '2025-06-01T10:00:00Z',
        scheduledDate: '2025-06-10',
        address: '123 Local St',
      );
      final cloud = _baseJob(
        restaurantName: 'Cloud Name',
        updatedAt: '2025-06-01T12:00:00Z',
        scheduledDate: '2025-06-15',
        address: '456 Cloud Ave',
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);

      expect(merged.restaurantName, 'Cloud Name');
      expect(merged.scheduledDate, '2025-06-15');
      expect(merged.address, '456 Cloud Ave');
      expect(merged.updatedAt, cloud.updatedAt);
    });

    test('local-newer keeps scheduling fields', () {
      final local = _baseJob(
        restaurantName: 'Local Name',
        updatedAt: '2025-06-01T14:00:00Z',
        scheduledDate: '2025-06-10',
      );
      final cloud = _baseJob(
        restaurantName: 'Cloud Name',
        updatedAt: '2025-06-01T12:00:00Z',
        scheduledDate: '2025-06-15',
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);

      expect(merged.restaurantName, 'Local Name');
      expect(merged.scheduledDate, '2025-06-10');
      expect(merged.updatedAt, local.updatedAt);
    });

    test('null updatedAt treated as epoch (other side wins)', () {
      final local = _baseJob(restaurantName: 'Local', updatedAt: null);
      final cloud = _baseJob(
        restaurantName: 'Cloud',
        updatedAt: '2025-06-01T12:00:00Z',
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.restaurantName, 'Cloud');
    });

    test('both null updatedAt keeps local', () {
      final local = _baseJob(restaurantName: 'Local', updatedAt: null);
      final cloud = _baseJob(restaurantName: 'Cloud', updatedAt: null);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.restaurantName, 'Local');
    });

    test('schemaVersion takes max', () {
      final local = _baseJob(schemaVersion: 2);
      final cloud = _baseJob(schemaVersion: 3);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.schemaVersion, 3);
    });

    test('immutable fields always from local', () {
      final local = _baseJob(jobId: 'local-id');
      final cloud = _baseJob(
        jobId: 'cloud-id',
        updatedAt: '2099-01-01T00:00:00Z',
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.jobId, 'local-id');
      expect(merged.shiftStartDate, local.shiftStartDate);
      expect(merged.createdAt, local.createdAt);
    });
  });

  group('JobMerger — photo merge (append-only)', () {
    test('union of photos by photoId', () {
      final local = _baseJob(preCleanLayoutPhotos: [_photo(id: 'p1')]);
      final cloud = _baseJob(preCleanLayoutPhotos: [_photo(id: 'p2')]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.preCleanLayoutPhotos, hasLength(2));
      expect(
        merged.preCleanLayoutPhotos.map((p) => p.photoId),
        containsAll(['p1', 'p2']),
      );
    });

    test('local order preserved, cloud appended', () {
      final local = _baseJob(
        preCleanLayoutPhotos: [_photo(id: 'p2'), _photo(id: 'p1')],
      );
      final cloud = _baseJob(
        preCleanLayoutPhotos: [_photo(id: 'p3'), _photo(id: 'p1')],
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      final ids = merged.preCleanLayoutPhotos.map((p) => p.photoId).toList();
      expect(ids, ['p2', 'p1', 'p3']);
    });

    test('sync status upgraded from cloud', () {
      final local = _baseJob(
        preCleanLayoutPhotos: [_photo(id: 'p1', syncStatus: null)],
      );
      final cloud = _baseJob(
        preCleanLayoutPhotos: [
          _photo(
            id: 'p1',
            syncStatus: 'synced',
            cloudUrl: 'https://example.com/p1.jpg',
            uploadedBy: 'user-a',
          ),
        ],
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      final p = merged.preCleanLayoutPhotos.first;
      expect(p.syncStatus, 'synced');
      expect(p.cloudUrl, 'https://example.com/p1.jpg');
      expect(p.uploadedBy, 'user-a');
    });

    test('local sync status kept when already better', () {
      final local = _baseJob(
        preCleanLayoutPhotos: [
          _photo(
            id: 'p1',
            syncStatus: 'synced',
            cloudUrl: 'https://local.com/p1.jpg',
          ),
        ],
      );
      final cloud = _baseJob(
        preCleanLayoutPhotos: [
          _photo(id: 'p1', syncStatus: 'pending'),
        ],
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      final p = merged.preCleanLayoutPhotos.first;
      expect(p.syncStatus, 'synced');
      expect(p.cloudUrl, 'https://local.com/p1.jpg');
    });

    test('cloud deletion propagates to local', () {
      final local = _baseJob(
        preCleanLayoutPhotos: [_photo(id: 'p1')],
      );
      final cloud = _baseJob(
        preCleanLayoutPhotos: [
          _photo(
            id: 'p1',
            status: 'deleted',
            deletedAt: '2025-06-01T12:00:00Z',
          ),
        ],
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      final p = merged.preCleanLayoutPhotos.first;
      expect(p.isDeleted, isTrue);
      expect(p.deletedAt, '2025-06-01T12:00:00Z');
    });

    test('already-deleted local stays deleted', () {
      final local = _baseJob(
        preCleanLayoutPhotos: [
          _photo(
            id: 'p1',
            status: 'deleted',
            deletedAt: '2025-05-01T00:00:00Z',
          ),
        ],
      );
      final cloud = _baseJob(
        preCleanLayoutPhotos: [_photo(id: 'p1')],
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.preCleanLayoutPhotos.first.isDeleted, isTrue);
    });

    test('local filesystem fields preserved during sync merge', () {
      final local = _baseJob(
        preCleanLayoutPhotos: [
          _photo(id: 'p1', subPhase: 'filters-on'),
        ],
      );
      final cloud = _baseJob(
        preCleanLayoutPhotos: [
          _photo(
            id: 'p1',
            syncStatus: 'synced',
            cloudUrl: 'https://example.com/p1.jpg',
          ),
        ],
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      final p = merged.preCleanLayoutPhotos.first;
      expect(p.subPhase, 'filters-on');
      expect(p.relativePath, 'photos/p1.jpg');
      expect(p.syncStatus, 'synced');
    });
  });

  group('JobMerger — unit merge', () {
    test('units matched by unitId, photos merged within', () {
      final local = _baseJob(units: [
        _unit(id: 'u1', before: [_photo(id: 'p1')]),
      ]);
      final cloud = _baseJob(units: [
        _unit(id: 'u1', before: [_photo(id: 'p1'), _photo(id: 'p2')]),
      ]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.units, hasLength(1));
      expect(merged.units.first.photosBefore, hasLength(2));
    });

    test('cloud-only unit appended', () {
      final local = _baseJob(units: [_unit(id: 'u1')]);
      final cloud = _baseJob(units: [_unit(id: 'u1'), _unit(id: 'u2')]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.units, hasLength(2));
      expect(merged.units.last.unitId, 'u2');
    });

    test('local-only unit kept', () {
      final local = _baseJob(units: [_unit(id: 'u1'), _unit(id: 'u3')]);
      final cloud = _baseJob(units: [_unit(id: 'u1')]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.units, hasLength(2));
      expect(merged.units.map((u) => u.unitId), containsAll(['u1', 'u3']));
    });

    test('after-photos also merged within units', () {
      final local = _baseJob(units: [
        _unit(id: 'u1', after: [_photo(id: 'a1')]),
      ]);
      final cloud = _baseJob(units: [
        _unit(id: 'u1', after: [_photo(id: 'a2')]),
      ]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.units.first.photosAfter, hasLength(2));
    });
  });

  group('JobMerger — video merge', () {
    test('exit videos unioned by videoId', () {
      final local = _baseJob(
        videos: Videos(exit: [_video(id: 'v1')], other: const []),
      );
      final cloud = _baseJob(
        videos: Videos(exit: [_video(id: 'v2')], other: const []),
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.videos.exit, hasLength(2));
    });

    test('video sync status upgraded from cloud', () {
      final local = _baseJob(
        videos: Videos(
          exit: [_video(id: 'v1', syncStatus: null)],
          other: const [],
        ),
      );
      final cloud = _baseJob(
        videos: Videos(
          exit: [
            _video(
              id: 'v1',
              syncStatus: 'synced',
              cloudUrl: 'https://example.com/v1.mp4',
              uploadedBy: 'user-b',
            ),
          ],
          other: const [],
        ),
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      final v = merged.videos.exit.first;
      expect(v.syncStatus, 'synced');
      expect(v.cloudUrl, 'https://example.com/v1.mp4');
      expect(v.uploadedBy, 'user-b');
    });

    test('video deletion from cloud propagates', () {
      final local = _baseJob(
        videos: Videos(
          exit: const [],
          other: [_video(id: 'v1')],
        ),
      );
      final cloud = _baseJob(
        videos: Videos(
          exit: const [],
          other: [
            _video(
              id: 'v1',
              status: 'deleted',
              deletedAt: '2025-06-01T00:00:00Z',
            ),
          ],
        ),
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.videos.other.first.isDeleted, isTrue);
    });
  });

  group('JobMerger — note merge', () {
    test('job notes unioned by noteId', () {
      final local = _baseJob(notes: [_note(id: 'n1')]);
      final cloud = _baseJob(notes: [_note(id: 'n2')]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.notes, hasLength(2));
    });

    test('cloud deletion propagates to local note', () {
      final local = _baseJob(notes: [_note(id: 'n1')]);
      final cloud = _baseJob(notes: [_note(id: 'n1', status: 'deleted')]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.notes.first.isDeleted, isTrue);
    });

    test('local text preserved for same noteId (both active)', () {
      final local = _baseJob(notes: [_note(id: 'n1', text: 'local text')]);
      final cloud = _baseJob(notes: [_note(id: 'n1', text: 'cloud text')]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.notes.first.text, 'local text');
    });

    test('manager notes unioned by noteId', () {
      final local = _baseJob(managerNotes: [_mgrNote(id: 'm1')]);
      final cloud = _baseJob(managerNotes: [_mgrNote(id: 'm2')]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.managerNotes, hasLength(2));
    });

    test('manager note cloud deletion propagates', () {
      final local = _baseJob(managerNotes: [_mgrNote(id: 'm1')]);
      final cloud =
          _baseJob(managerNotes: [_mgrNote(id: 'm1', status: 'deleted')]);

      final merged = JobMerger.merge(local: local, cloud: cloud);
      expect(merged.managerNotes.first.isDeleted, isTrue);
    });
  });

  group('JobMerger — combined scenario', () {
    test('full multi-device merge', () {
      final local = _baseJob(
        restaurantName: 'Local',
        updatedAt: '2025-06-01T10:00:00Z',
        units: [
          _unit(
            id: 'u1',
            before: [_photo(id: 'p1')],
            after: [_photo(id: 'a1')],
          ),
        ],
        notes: [_note(id: 'n1', text: 'local note')],
        preCleanLayoutPhotos: [_photo(id: 'lp1')],
        videos: Videos(exit: [_video(id: 'v1')], other: const []),
      );

      final cloud = _baseJob(
        restaurantName: 'Cloud',
        updatedAt: '2025-06-01T14:00:00Z',
        units: [
          _unit(
            id: 'u1',
            before: [
              _photo(id: 'p1', syncStatus: 'synced', cloudUrl: 'https://p1'),
              _photo(id: 'p2', uploadedBy: 'user-b'),
            ],
          ),
          _unit(id: 'u2'),
        ],
        notes: [
          _note(id: 'n1', text: 'cloud note'),
          _note(id: 'n2', text: 'new cloud note'),
        ],
        preCleanLayoutPhotos: [_photo(id: 'lp1'), _photo(id: 'lp2')],
        videos: Videos(
          exit: [_video(id: 'v1', syncStatus: 'synced')],
          other: [_video(id: 'v2')],
        ),
      );

      final merged = JobMerger.merge(local: local, cloud: cloud);

      // Cloud is newer — scheduling fields from cloud
      expect(merged.restaurantName, 'Cloud');

      // Units merged
      expect(merged.units, hasLength(2));
      expect(merged.units[0].photosBefore, hasLength(2));
      expect(merged.units[0].photosBefore.first.syncStatus, 'synced');
      expect(merged.units[0].photosAfter, hasLength(1));
      expect(merged.units[1].unitId, 'u2');

      // Notes merged
      expect(merged.notes, hasLength(2));
      expect(merged.notes[0].text, 'local note');

      // Layout photos merged
      expect(merged.preCleanLayoutPhotos, hasLength(2));

      // Videos merged
      expect(merged.videos.exit.first.syncStatus, 'synced');
      expect(merged.videos.other, hasLength(1));
    });
  });
}
