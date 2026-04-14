import 'dart:developer' as developer;
import 'dart:io';

import 'package:path/path.dart' as p;

import '../data/repositories/job_repository.dart';
import '../domain/models/job.dart';
import '../domain/models/photo_record.dart';
import '../domain/models/unit.dart';
import '../domain/models/video_record.dart';
import '../domain/models/videos.dart';
import 'storage_service.dart';

/// Coordinates uploading a single media file to Firebase Storage and
/// persisting the updated sync status back to job.json (and Firestore
/// via [CloudJobRepository]).
///
/// This is the atomic building block that the upload queue (Step 4b) will
/// call for each item in the queue.
class UploadController {
  UploadController({
    required this.storageService,
    required this.jobRepository,
    required this.currentUserId,
  });

  final StorageService storageService;
  final JobRepository jobRepository;
  final String currentUserId;

  /// Uploads a single photo and updates its sync metadata in the job.
  ///
  /// Returns the updated [PhotoRecord] on success, or null if the local
  /// file is missing or the job can't be loaded.
  Future<PhotoRecord?> uploadPhoto({
    required Directory jobDir,
    required String jobId,
    required String photoId,
  }) async {
    final job = await jobRepository.loadJob(jobDir);
    if (job == null) {
      developer.log(
        'Upload skipped: job.json not found in ${jobDir.path}',
        name: 'UploadController',
      );
      return null;
    }

    final found = _findPhoto(job, photoId);
    if (found == null) {
      developer.log(
        'Upload skipped: photoId $photoId not found in job',
        name: 'UploadController',
      );
      return null;
    }

    final photo = found.record;
    final localFile = File(p.join(jobDir.path, photo.relativePath));

    if (!localFile.existsSync()) {
      developer.log(
        'Upload skipped: local file missing at ${localFile.path}',
        name: 'UploadController',
      );

      if (photo.syncStatus == 'uploading' || photo.syncStatus == 'pending') {
        final errored = photo.copyWith(syncStatus: 'error');
        await _replacePhotoInJob(jobDir, job, found, errored);
      }

      return null;
    }

    // Mark as uploading
    final uploading = photo.copyWith(syncStatus: 'uploading');
    await _replacePhotoInJob(jobDir, job, found, uploading);

    try {
      final downloadUrl = await storageService.uploadPhoto(
        jobId: jobId,
        relativePath: photo.relativePath,
        file: localFile,
      );

      final synced = uploading.copyWith(
        syncStatus: 'synced',
        cloudUrl: downloadUrl,
        uploadedBy: currentUserId,
        clearSourcePath: true,
      );
      await _deleteSourceBackup(photo.sourcePath);

      final freshJob = await jobRepository.loadJob(jobDir);
      if (freshJob != null) {
        final freshFound = _findPhoto(freshJob, photoId);
        if (freshFound != null) {
          await _replacePhotoInJob(jobDir, freshJob, freshFound, synced);
        }
      }

      return synced;
    } catch (e, st) {
      developer.log(
        'Upload failed for photoId $photoId: $e',
        name: 'UploadController',
        error: e,
        stackTrace: st,
      );

      final freshJob = await jobRepository.loadJob(jobDir);
      if (freshJob != null) {
        final freshFound = _findPhoto(freshJob, photoId);
        if (freshFound != null) {
          final errored = freshFound.record.copyWith(syncStatus: 'error');
          await _replacePhotoInJob(jobDir, freshJob, freshFound, errored);
        }
      }

      return null;
    }
  }

  /// Uploads a single video and updates its sync metadata in the job.
  ///
  /// Returns the updated [VideoRecord] on success, or null on failure.
  Future<VideoRecord?> uploadVideo({
    required Directory jobDir,
    required String jobId,
    required String videoId,
  }) async {
    final job = await jobRepository.loadJob(jobDir);
    if (job == null) return null;

    final found = _findVideo(job, videoId);
    if (found == null) {
      developer.log(
        'Upload skipped: videoId $videoId not found in job',
        name: 'UploadController',
      );
      return null;
    }

    final video = found.record;
    final localFile = File(p.join(jobDir.path, video.relativePath));

    if (!localFile.existsSync()) {
      developer.log(
        'Upload skipped: local file missing at ${localFile.path}',
        name: 'UploadController',
      );

      if (video.syncStatus == 'uploading' || video.syncStatus == 'pending') {
        final errored = video.copyWith(syncStatus: 'error');
        await _replaceVideoInJob(jobDir, job, found, errored);
      }

      return null;
    }

    final uploading = video.copyWith(syncStatus: 'uploading');
    await _replaceVideoInJob(jobDir, job, found, uploading);

    try {
      final downloadUrl = await storageService.uploadVideo(
        jobId: jobId,
        relativePath: video.relativePath,
        file: localFile,
      );

      final synced = uploading.copyWith(
        syncStatus: 'synced',
        cloudUrl: downloadUrl,
        uploadedBy: currentUserId,
        clearSourcePath: true,
      );
      await _deleteSourceBackup(video.sourcePath);

      final freshJob = await jobRepository.loadJob(jobDir);
      if (freshJob != null) {
        final freshFound = _findVideo(freshJob, videoId);
        if (freshFound != null) {
          await _replaceVideoInJob(jobDir, freshJob, freshFound, synced);
        }
      }

      return synced;
    } catch (e, st) {
      developer.log(
        'Upload failed for videoId $videoId: $e',
        name: 'UploadController',
        error: e,
        stackTrace: st,
      );

      final freshJob = await jobRepository.loadJob(jobDir);
      if (freshJob != null) {
        final freshFound = _findVideo(freshJob, videoId);
        if (freshFound != null) {
          final errored = freshFound.record.copyWith(syncStatus: 'error');
          await _replaceVideoInJob(jobDir, freshJob, freshFound, errored);
        }
      }

      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // Photo location helpers
  // ---------------------------------------------------------------------------

  _PhotoLocation? _findPhoto(Job job, String photoId) {
    // Check preCleanLayoutPhotos
    for (var i = 0; i < job.preCleanLayoutPhotos.length; i++) {
      if (job.preCleanLayoutPhotos[i].photoId == photoId) {
        return _PhotoLocation(
          record: job.preCleanLayoutPhotos[i],
          locationKind: _PhotoLocationKind.preCleanLayout,
          index: i,
        );
      }
    }

    // Check each unit's before/after lists
    for (var ui = 0; ui < job.units.length; ui++) {
      final unit = job.units[ui];
      for (var pi = 0; pi < unit.photosBefore.length; pi++) {
        if (unit.photosBefore[pi].photoId == photoId) {
          return _PhotoLocation(
            record: unit.photosBefore[pi],
            locationKind: _PhotoLocationKind.unitBefore,
            unitIndex: ui,
            index: pi,
          );
        }
      }
      for (var pi = 0; pi < unit.photosAfter.length; pi++) {
        if (unit.photosAfter[pi].photoId == photoId) {
          return _PhotoLocation(
            record: unit.photosAfter[pi],
            locationKind: _PhotoLocationKind.unitAfter,
            unitIndex: ui,
            index: pi,
          );
        }
      }
    }

    return null;
  }

  Future<void> _replacePhotoInJob(
    Directory jobDir,
    Job job,
    _PhotoLocation location,
    PhotoRecord replacement,
  ) async {
    Job updated;

    switch (location.locationKind) {
      case _PhotoLocationKind.preCleanLayout:
        final list = List<PhotoRecord>.from(job.preCleanLayoutPhotos);
        list[location.index] = replacement;
        updated = job.copyWith(preCleanLayoutPhotos: list);

      case _PhotoLocationKind.unitBefore:
        final units = List<Unit>.from(job.units);
        final unit = units[location.unitIndex!];
        final photos = List<PhotoRecord>.from(unit.photosBefore);
        photos[location.index] = replacement;
        units[location.unitIndex!] = unit.copyWith(photosBefore: photos);
        updated = job.copyWith(units: units);

      case _PhotoLocationKind.unitAfter:
        final units = List<Unit>.from(job.units);
        final unit = units[location.unitIndex!];
        final photos = List<PhotoRecord>.from(unit.photosAfter);
        photos[location.index] = replacement;
        units[location.unitIndex!] = unit.copyWith(photosAfter: photos);
        updated = job.copyWith(units: units);
    }

    await jobRepository.saveJob(jobDir, updated);
  }

  // ---------------------------------------------------------------------------
  // Video location helpers
  // ---------------------------------------------------------------------------

  _VideoLocation? _findVideo(Job job, String videoId) {
    for (var i = 0; i < job.videos.exit.length; i++) {
      if (job.videos.exit[i].videoId == videoId) {
        return _VideoLocation(
          record: job.videos.exit[i],
          isExit: true,
          index: i,
        );
      }
    }
    for (var i = 0; i < job.videos.other.length; i++) {
      if (job.videos.other[i].videoId == videoId) {
        return _VideoLocation(
          record: job.videos.other[i],
          isExit: false,
          index: i,
        );
      }
    }
    return null;
  }

  Future<void> _replaceVideoInJob(
    Directory jobDir,
    Job job,
    _VideoLocation location,
    VideoRecord replacement,
  ) async {
    final exitList = List<VideoRecord>.from(job.videos.exit);
    final otherList = List<VideoRecord>.from(job.videos.other);

    if (location.isExit) {
      exitList[location.index] = replacement;
    } else {
      otherList[location.index] = replacement;
    }

    final updated = job.copyWith(
      videos: Videos(exit: exitList, other: otherList),
    );
    await jobRepository.saveJob(jobDir, updated);
  }

  Future<void> _deleteSourceBackup(String? sourcePath) async {
    if (sourcePath == null || sourcePath.isEmpty) return;
    final sourceFile = File(sourcePath);
    if (!sourceFile.existsSync()) return;
    try {
      await sourceFile.delete();
    } catch (_) {
      // Backup cleanup is best-effort after a confirmed cloud upload.
    }
  }
}

// ---------------------------------------------------------------------------
// Internal helper types
// ---------------------------------------------------------------------------

enum _PhotoLocationKind { preCleanLayout, unitBefore, unitAfter }

class _PhotoLocation {
  const _PhotoLocation({
    required this.record,
    required this.locationKind,
    required this.index,
    this.unitIndex,
  });

  final PhotoRecord record;
  final _PhotoLocationKind locationKind;
  final int index;
  final int? unitIndex;
}

class _VideoLocation {
  const _VideoLocation({
    required this.record,
    required this.isExit,
    required this.index,
  });

  final VideoRecord record;
  final bool isExit;
  final int index;
}
