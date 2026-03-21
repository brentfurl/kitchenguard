import 'package:flutter_test/flutter_test.dart';
import 'package:kitchenguard_photo_organizer/domain/models/day_note.dart';
import 'package:kitchenguard_photo_organizer/domain/models/job.dart';
import 'package:kitchenguard_photo_organizer/domain/models/job_note.dart';
import 'package:kitchenguard_photo_organizer/domain/models/photo_record.dart';
import 'package:kitchenguard_photo_organizer/domain/models/unit.dart';
import 'package:kitchenguard_photo_organizer/domain/models/video_record.dart';
import 'package:kitchenguard_photo_organizer/domain/models/videos.dart';

void main() {
  // ---------------------------------------------------------------------------
  // PhotoRecord
  // ---------------------------------------------------------------------------
  group('PhotoRecord', () {
    final fullJson = <String, dynamic>{
      'photoId': 'abc-123',
      'fileName': 'hood_1_before.jpg',
      'relativePath': 'Hoods/hood_1__unit-abc/Before/hood_1_before.jpg',
      'capturedAt': '2026-03-06T14:00:00.000Z',
      'status': 'local',
      'missingLocal': false,
      'recovered': false,
    };

    test('fromJson / toJson round-trip preserves all fields', () {
      final record = PhotoRecord.fromJson(fullJson);
      final back = record.toJson();
      expect(back['photoId'], 'abc-123');
      expect(back['fileName'], 'hood_1_before.jpg');
      expect(back['relativePath'],
          'Hoods/hood_1__unit-abc/Before/hood_1_before.jpg');
      expect(back['capturedAt'], '2026-03-06T14:00:00.000Z');
      expect(back['status'], 'local');
      expect(back['missingLocal'], false);
      expect(back['recovered'], false);
    });

    test('fromJson uses defaults for missing fields', () {
      final record = PhotoRecord.fromJson({'fileName': 'x.jpg', 'relativePath': 'x.jpg', 'capturedAt': 'now'});
      expect(record.photoId, '');
      expect(record.status, 'local');
      expect(record.missingLocal, false);
      expect(record.recovered, false);
      expect(record.deletedAt, isNull);
    });

    test('fromJson normalizes unknown status to local', () {
      final record = PhotoRecord.fromJson({
        ...fullJson,
        'status': 'some_future_status',
      });
      expect(record.status, 'local');
    });

    test('isActive: local and not missing', () {
      final r = PhotoRecord.fromJson(fullJson);
      expect(r.isActive, isTrue);
      expect(r.isDeleted, isFalse);
      expect(r.isMissing, isFalse);
    });

    test('isDeleted when status is deleted', () {
      final r = PhotoRecord.fromJson({...fullJson, 'status': 'deleted'});
      expect(r.isDeleted, isTrue);
      expect(r.isActive, isFalse);
    });

    test('isMissing when status is missing_local', () {
      final r = PhotoRecord.fromJson({...fullJson, 'status': 'missing_local'});
      expect(r.isMissing, isTrue);
      expect(r.isActive, isFalse);
    });

    test('isMissing when missingLocal flag is true', () {
      final r = PhotoRecord.fromJson({...fullJson, 'missingLocal': true});
      expect(r.isMissing, isTrue);
      expect(r.isActive, isFalse);
    });

    test('deletedAt round-trips when present', () {
      final r = PhotoRecord.fromJson({
        ...fullJson,
        'status': 'deleted',
        'deletedAt': '2026-03-07T10:00:00.000Z',
      });
      expect(r.deletedAt, '2026-03-07T10:00:00.000Z');
      expect(r.toJson()['deletedAt'], '2026-03-07T10:00:00.000Z');
    });

    test('deletedAt is absent from toJson when null', () {
      final r = PhotoRecord.fromJson(fullJson);
      expect(r.toJson().containsKey('deletedAt'), isFalse);
    });

    test('copyWith produces independent copy', () {
      final r = PhotoRecord.fromJson(fullJson);
      final copy = r.copyWith(status: 'deleted');
      expect(copy.status, 'deleted');
      expect(r.status, 'local');
    });
  });

  // ---------------------------------------------------------------------------
  // VideoRecord
  // ---------------------------------------------------------------------------
  group('VideoRecord', () {
    final fullJson = <String, dynamic>{
      'videoId': 'vid-001',
      'fileName': 'exit_video.mp4',
      'relativePath': 'Videos/Exit/exit_video.mp4',
      'capturedAt': '2026-03-06T18:00:00.000Z',
      'status': 'local',
    };

    test('fromJson / toJson round-trip preserves all fields', () {
      final v = VideoRecord.fromJson(fullJson);
      final back = v.toJson();
      expect(back['videoId'], 'vid-001');
      expect(back['fileName'], 'exit_video.mp4');
      expect(back['relativePath'], 'Videos/Exit/exit_video.mp4');
      expect(back['capturedAt'], '2026-03-06T18:00:00.000Z');
      expect(back['status'], 'local');
    });

    test('fromJson uses defaults for missing fields', () {
      final v = VideoRecord.fromJson({'fileName': 'v.mp4', 'relativePath': 'v.mp4', 'capturedAt': 'now'});
      expect(v.videoId, '');
      expect(v.status, 'local');
      expect(v.deletedAt, isNull);
    });

    test('isActive when status is local', () {
      final v = VideoRecord.fromJson(fullJson);
      expect(v.isActive, isTrue);
      expect(v.isDeleted, isFalse);
    });

    test('isDeleted when status is deleted', () {
      final v = VideoRecord.fromJson({...fullJson, 'status': 'deleted'});
      expect(v.isDeleted, isTrue);
      expect(v.isActive, isFalse);
    });

    test('non-deleted status normalizes to local', () {
      final v = VideoRecord.fromJson({...fullJson, 'status': 'unknown_status'});
      expect(v.status, 'local');
    });

    test('deletedAt round-trips when present', () {
      final v = VideoRecord.fromJson({
        ...fullJson,
        'status': 'deleted',
        'deletedAt': '2026-03-07T12:00:00.000Z',
      });
      expect(v.deletedAt, '2026-03-07T12:00:00.000Z');
      expect(v.toJson()['deletedAt'], '2026-03-07T12:00:00.000Z');
    });

    test('deletedAt absent from toJson when null', () {
      final v = VideoRecord.fromJson(fullJson);
      expect(v.toJson().containsKey('deletedAt'), isFalse);
    });

    test('copyWith produces independent copy', () {
      final v = VideoRecord.fromJson(fullJson);
      final copy = v.copyWith(status: 'deleted');
      expect(copy.status, 'deleted');
      expect(v.status, 'local');
    });
  });

  // ---------------------------------------------------------------------------
  // Videos
  // ---------------------------------------------------------------------------
  group('Videos', () {
    test('fromJson / toJson round-trip with populated lists', () {
      final json = {
        'exit': [
          {'videoId': 'e1', 'fileName': 'exit1.mp4', 'relativePath': 'Videos/Exit/exit1.mp4', 'capturedAt': 'now', 'status': 'local'},
        ],
        'other': [
          {'videoId': 'o1', 'fileName': 'other1.mp4', 'relativePath': 'Videos/Other/other1.mp4', 'capturedAt': 'now', 'status': 'local'},
        ],
      };
      final videos = Videos.fromJson(json);
      expect(videos.exit.length, 1);
      expect(videos.other.length, 1);
      expect(videos.exit.first.videoId, 'e1');
      expect(videos.other.first.videoId, 'o1');

      final back = videos.toJson();
      expect((back['exit'] as List).length, 1);
      expect((back['other'] as List).length, 1);
    });

    test('Videos.empty has empty lists', () {
      const v = Videos.empty();
      expect(v.exit, isEmpty);
      expect(v.other, isEmpty);
    });

    test('fromJson handles missing exit/other gracefully', () {
      final v = Videos.fromJson({});
      expect(v.exit, isEmpty);
      expect(v.other, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // JobNote
  // ---------------------------------------------------------------------------
  group('JobNote', () {
    final fullJson = <String, dynamic>{
      'noteId': 'note-001',
      'text': 'Needs grease pillow',
      'createdAt': '2026-03-06T15:00:00.000Z',
      'status': 'active',
    };

    test('fromJson / toJson round-trip preserves all fields', () {
      final n = JobNote.fromJson(fullJson);
      final back = n.toJson();
      expect(back['noteId'], 'note-001');
      expect(back['text'], 'Needs grease pillow');
      expect(back['createdAt'], '2026-03-06T15:00:00.000Z');
      expect(back['status'], 'active');
    });

    test('fromJson uses defaults for missing fields', () {
      final n = JobNote.fromJson({'text': 'hi', 'createdAt': 'now'});
      expect(n.noteId, '');
      expect(n.status, 'active');
    });

    test('copyWith produces independent copy', () {
      final n = JobNote.fromJson(fullJson);
      final copy = n.copyWith(status: 'deleted');
      expect(copy.status, 'deleted');
      expect(n.status, 'active');
    });
  });

  // ---------------------------------------------------------------------------
  // Unit
  // ---------------------------------------------------------------------------
  group('Unit', () {
    PhotoRecord activePhoto(String id) => PhotoRecord(
          photoId: id,
          fileName: '$id.jpg',
          relativePath: '$id.jpg',
          capturedAt: 'now',
          status: 'local',
          missingLocal: false,
          recovered: false,
        );

    PhotoRecord deletedPhoto(String id) => PhotoRecord(
          photoId: id,
          fileName: '$id.jpg',
          relativePath: '$id.jpg',
          capturedAt: 'now',
          status: 'deleted',
          missingLocal: false,
          recovered: false,
        );

    PhotoRecord missingPhoto(String id) => PhotoRecord(
          photoId: id,
          fileName: '$id.jpg',
          relativePath: '$id.jpg',
          capturedAt: 'now',
          status: 'missing_local',
          missingLocal: true,
          recovered: false,
        );

    test('fromJson / toJson round-trip preserves all fields', () {
      final json = {
        'unitId': 'unit-001',
        'type': 'hood',
        'name': 'hood 1',
        'unitFolderName': 'hood_1__unit-001',
        'isComplete': false,
        'photosBefore': [],
        'photosAfter': [],
      };
      final u = Unit.fromJson(json);
      final back = u.toJson();
      expect(back['unitId'], 'unit-001');
      expect(back['type'], 'hood');
      expect(back['name'], 'hood 1');
      expect(back['unitFolderName'], 'hood_1__unit-001');
      expect(back['isComplete'], false);
    });

    test('fromJson uses defaults for missing fields', () {
      final u = Unit.fromJson({'unitId': 'x', 'type': 'hood', 'name': 'h', 'unitFolderName': 'h'});
      expect(u.isComplete, false);
      expect(u.completedAt, isNull);
      expect(u.photosBefore, isEmpty);
      expect(u.photosAfter, isEmpty);
    });

    test('completedAt round-trips when present', () {
      final json = {
        'unitId': 'u1', 'type': 'hood', 'name': 'hood 1', 'unitFolderName': 'hood_1',
        'isComplete': true, 'completedAt': '2026-03-06T16:00:00.000Z',
        'photosBefore': [], 'photosAfter': [],
      };
      final u = Unit.fromJson(json);
      expect(u.completedAt, '2026-03-06T16:00:00.000Z');
      expect(u.toJson()['completedAt'], '2026-03-06T16:00:00.000Z');
    });

    test('completedAt absent from toJson when null', () {
      final u = Unit.fromJson({'unitId': 'u1', 'type': 'hood', 'name': 'h', 'unitFolderName': 'h'});
      expect(u.toJson().containsKey('completedAt'), isFalse);
    });

    test('visibleBeforeCount counts only active photos', () {
      final u = Unit(
        unitId: 'u1', type: 'hood', name: 'hood 1', unitFolderName: 'hood_1',
        isComplete: false,
        photosBefore: [activePhoto('a'), deletedPhoto('b'), missingPhoto('c'), activePhoto('d')],
        photosAfter: [],
      );
      expect(u.visibleBeforeCount, 2);
    });

    test('visibleAfterCount counts only active photos', () {
      final u = Unit(
        unitId: 'u1', type: 'hood', name: 'hood 1', unitFolderName: 'hood_1',
        isComplete: false,
        photosBefore: [],
        photosAfter: [activePhoto('x'), deletedPhoto('y')],
      );
      expect(u.visibleAfterCount, 1);
    });

    test('visibleBeforeCount is 0 when all photos are non-active', () {
      final u = Unit(
        unitId: 'u1', type: 'fan', name: 'fan 1', unitFolderName: 'fan_1',
        isComplete: false,
        photosBefore: [deletedPhoto('a'), missingPhoto('b')],
        photosAfter: [],
      );
      expect(u.visibleBeforeCount, 0);
    });

    test('nested photos survive fromJson / toJson round-trip', () {
      final json = {
        'unitId': 'u1', 'type': 'hood', 'name': 'hood 1', 'unitFolderName': 'hood_1',
        'isComplete': false,
        'photosBefore': [
          {'photoId': 'p1', 'fileName': 'p1.jpg', 'relativePath': 'p1.jpg', 'capturedAt': 'now', 'status': 'local', 'missingLocal': false, 'recovered': false},
        ],
        'photosAfter': [],
      };
      final u = Unit.fromJson(json);
      expect(u.photosBefore.length, 1);
      expect(u.photosBefore.first.photoId, 'p1');
      final back = u.toJson();
      expect((back['photosBefore'] as List).length, 1);
      expect((back['photosBefore'] as List).first['photoId'], 'p1');
    });
  });

  // ---------------------------------------------------------------------------
  // Job
  // ---------------------------------------------------------------------------
  group('Job', () {
    Map<String, dynamic> minimalJobJson() => {
          'jobId': 'job-001',
          'restaurantName': 'Test Restaurant',
          'shiftStartDate': '2026-03-06',
          'createdAt': '2026-03-06T14:00:00.000Z',
          'updatedAt': '2026-03-06T15:00:00.000Z',
          'schemaVersion': 2,
          'units': [],
          'notes': [],
          'preCleanLayoutPhotos': [],
          'videos': {'exit': [], 'other': []},
        };

    test('fromJson / toJson round-trip preserves top-level fields', () {
      final job = Job.fromJson(minimalJobJson());
      final back = job.toJson();
      expect(back['jobId'], 'job-001');
      expect(back['restaurantName'], 'Test Restaurant');
      expect(back['shiftStartDate'], '2026-03-06');
      expect(back['createdAt'], '2026-03-06T14:00:00.000Z');
      expect(back['updatedAt'], '2026-03-06T15:00:00.000Z');
      expect(back['schemaVersion'], 2);
    });

    test('fromJson handles missing updatedAt (schema version 1 data)', () {
      final json = minimalJobJson()..remove('updatedAt');
      final job = Job.fromJson(json);
      expect(job.updatedAt, isNull);
      expect(job.toJson().containsKey('updatedAt'), isFalse);
    });

    test('fromJson defaults schemaVersion to 1 when absent', () {
      final json = minimalJobJson()..remove('schemaVersion');
      final job = Job.fromJson(json);
      expect(job.schemaVersion, 1);
    });

    test('fromJson handles missing units/notes/photos gracefully', () {
      final json = {
        'jobId': 'j1',
        'restaurantName': 'R',
        'shiftStartDate': '2026-03-06',
        'createdAt': 'now',
        'schemaVersion': 2,
      };
      final job = Job.fromJson(json);
      expect(job.units, isEmpty);
      expect(job.notes, isEmpty);
      expect(job.preCleanLayoutPhotos, isEmpty);
      expect(job.videos.exit, isEmpty);
      expect(job.videos.other, isEmpty);
    });

    test('nested units survive fromJson / toJson round-trip', () {
      final json = minimalJobJson();
      json['units'] = [
        {
          'unitId': 'u1', 'type': 'hood', 'name': 'hood 1', 'unitFolderName': 'hood_1',
          'isComplete': false, 'photosBefore': [], 'photosAfter': [],
        }
      ];
      final job = Job.fromJson(json);
      expect(job.units.length, 1);
      expect(job.units.first.name, 'hood 1');
      final back = job.toJson();
      expect((back['units'] as List).length, 1);
      expect((back['units'] as List).first['name'], 'hood 1');
    });

    test('nested notes survive fromJson / toJson round-trip', () {
      final json = minimalJobJson();
      json['notes'] = [
        {'noteId': 'n1', 'text': 'check pilot lights', 'createdAt': 'now', 'status': 'active'},
      ];
      final job = Job.fromJson(json);
      expect(job.notes.length, 1);
      expect(job.notes.first.text, 'check pilot lights');
    });

    test('nested preCleanLayoutPhotos survive round-trip', () {
      final json = minimalJobJson();
      json['preCleanLayoutPhotos'] = [
        {'photoId': 'pc1', 'fileName': 'layout.jpg', 'relativePath': 'PreCleanLayout/layout.jpg', 'capturedAt': 'now', 'status': 'local', 'missingLocal': false, 'recovered': false},
      ];
      final job = Job.fromJson(json);
      expect(job.preCleanLayoutPhotos.length, 1);
      expect(job.preCleanLayoutPhotos.first.photoId, 'pc1');
    });

    test('copyWith produces independent copy with updated field', () {
      final job = Job.fromJson(minimalJobJson());
      final copy = job.copyWith(restaurantName: 'New Restaurant');
      expect(copy.restaurantName, 'New Restaurant');
      expect(job.restaurantName, 'Test Restaurant');
    });

    test('copyWith with updatedAt replaces value', () {
      final job = Job.fromJson(minimalJobJson());
      final copy = job.copyWith(updatedAt: '2026-03-06T20:00:00.000Z');
      expect(copy.updatedAt, '2026-03-06T20:00:00.000Z');
      expect(job.updatedAt, '2026-03-06T15:00:00.000Z');
    });

    test('fromJson defaults scheduledDate and sortOrder to null when absent', () {
      final job = Job.fromJson(minimalJobJson());
      expect(job.scheduledDate, isNull);
      expect(job.sortOrder, isNull);
    });

    test('fromJson parses scheduledDate and sortOrder when present', () {
      final json = minimalJobJson()
        ..['scheduledDate'] = '2026-03-20'
        ..['sortOrder'] = 3;
      final job = Job.fromJson(json);
      expect(job.scheduledDate, '2026-03-20');
      expect(job.sortOrder, 3);
    });

    test('toJson omits null scheduledDate and sortOrder', () {
      final job = Job.fromJson(minimalJobJson());
      final json = job.toJson();
      expect(json.containsKey('scheduledDate'), isFalse);
      expect(json.containsKey('sortOrder'), isFalse);
    });

    test('toJson includes scheduledDate and sortOrder when set', () {
      final json = minimalJobJson()
        ..['scheduledDate'] = '2026-04-01'
        ..['sortOrder'] = 0;
      final job = Job.fromJson(json);
      final back = job.toJson();
      expect(back['scheduledDate'], '2026-04-01');
      expect(back['sortOrder'], 0);
    });

    test('round-trip preserves scheduledDate and sortOrder', () {
      final json = minimalJobJson()
        ..['scheduledDate'] = '2026-05-15'
        ..['sortOrder'] = 2;
      final job = Job.fromJson(json);
      final rebuilt = Job.fromJson(job.toJson());
      expect(rebuilt.scheduledDate, '2026-05-15');
      expect(rebuilt.sortOrder, 2);
    });

    test('copyWith for scheduledDate and sortOrder', () {
      final job = Job.fromJson(minimalJobJson());
      final copy = job.copyWith(scheduledDate: '2026-06-01', sortOrder: 5);
      expect(copy.scheduledDate, '2026-06-01');
      expect(copy.sortOrder, 5);
      expect(job.scheduledDate, isNull);
      expect(job.sortOrder, isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // DayNote
  // ---------------------------------------------------------------------------
  group('DayNote', () {
    final fullJson = <String, dynamic>{
      'noteId': 'dn-001',
      'date': '2026-03-20',
      'text': 'Crew arrives at 6am, bring extra filters',
      'createdAt': '2026-03-19T22:00:00.000Z',
      'status': 'active',
    };

    test('fromJson / toJson round-trip preserves all fields', () {
      final note = DayNote.fromJson(fullJson);
      final back = note.toJson();
      expect(back['noteId'], 'dn-001');
      expect(back['date'], '2026-03-20');
      expect(back['text'], 'Crew arrives at 6am, bring extra filters');
      expect(back['createdAt'], '2026-03-19T22:00:00.000Z');
      expect(back['status'], 'active');
    });

    test('fromJson uses defaults for missing fields', () {
      final note = DayNote.fromJson({
        'date': '2026-03-20',
        'text': 'hello',
        'createdAt': 'now',
      });
      expect(note.noteId, '');
      expect(note.status, 'active');
    });

    test('fromJson normalizes unknown status to active', () {
      final note = DayNote.fromJson({
        ...fullJson,
        'status': 'some_future_status',
      });
      expect(note.status, 'active');
    });

    test('isActive when status is active', () {
      final note = DayNote.fromJson(fullJson);
      expect(note.isActive, isTrue);
      expect(note.isDeleted, isFalse);
    });

    test('isDeleted when status is deleted', () {
      final note = DayNote.fromJson({...fullJson, 'status': 'deleted'});
      expect(note.isDeleted, isTrue);
      expect(note.isActive, isFalse);
    });

    test('copyWith produces independent copy', () {
      final note = DayNote.fromJson(fullJson);
      final copy = note.copyWith(status: 'deleted');
      expect(copy.status, 'deleted');
      expect(note.status, 'active');
    });

    test('copyWith replaces date and text', () {
      final note = DayNote.fromJson(fullJson);
      final copy = note.copyWith(date: '2026-04-01', text: 'Updated note');
      expect(copy.date, '2026-04-01');
      expect(copy.text, 'Updated note');
      expect(note.date, '2026-03-20');
      expect(note.text, 'Crew arrives at 6am, bring extra filters');
    });

    test('full round-trip through fromJson/toJson/fromJson', () {
      final note = DayNote.fromJson(fullJson);
      final rebuilt = DayNote.fromJson(note.toJson());
      expect(rebuilt.noteId, note.noteId);
      expect(rebuilt.date, note.date);
      expect(rebuilt.text, note.text);
      expect(rebuilt.createdAt, note.createdAt);
      expect(rebuilt.status, note.status);
    });
  });
}
