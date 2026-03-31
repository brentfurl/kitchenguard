import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:uuid/uuid.dart';

import '../domain/models/upload_queue_entry.dart';
import '../storage/app_paths.dart';
import 'upload_controller.dart';

/// Manages a persistent queue of pending media uploads to Firebase Storage.
///
/// Queue entries are stored in `upload_queue.json` at the root of the
/// jobs directory (`KitchenCleaningJobs/`). The queue survives app restarts
/// and is the source of truth for which media files still need uploading.
///
/// New photos and videos are automatically enqueued after capture via
/// [JobsService]. The queue processor ([processNext] / [processAll])
/// delegates each upload to [UploadController] and tracks success/failure.
class UploadQueue {
  UploadQueue({required this.paths});

  final AppPaths paths;
  final Uuid _uuid = const Uuid();

  List<UploadQueueEntry> _entries = [];
  bool _loaded = false;

  /// Fires after a new entry is successfully enqueued.
  /// Used by the upload progress notifier to trigger immediate processing.
  void Function()? onNewEntry;

  static const int maxRetries = 10;
  static const String _fileName = 'upload_queue.json';

  /// Entries waiting to be uploaded right now.
  ///
  /// Failed entries are retried in background with backoff, but are not
  /// counted here to avoid a "stuck" pending badge in the UI.
  int get pendingCount => _entries.where((e) => e.isPending).length;

  /// Total entries in the queue (all statuses).
  int get totalCount => _entries.length;

  /// Read-only snapshot of all entries.
  List<UploadQueueEntry> get entries => List.unmodifiable(_entries);

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  /// Loads the queue from disk. Resets stale 'uploading' entries to 'pending'
  /// (covers the case where the app was killed mid-upload).
  Future<void> load() async {
    final file = await _queueFile();
    if (!await file.exists()) {
      _entries = [];
      _loaded = true;
      return;
    }

    try {
      final content = await file.readAsString();
      final List<dynamic> jsonList = jsonDecode(content) as List<dynamic>;
      _entries = jsonList
          .map((e) => UploadQueueEntry.fromJson(e as Map<String, dynamic>))
          .toList();

      var modified = false;
      for (var i = 0; i < _entries.length; i++) {
        if (_entries[i].isUploading) {
          _entries[i] = _entries[i].copyWith(status: 'pending');
          modified = true;
        }
      }

      if (modified) await _save();
      _loaded = true;
    } catch (e) {
      developer.log(
        'Failed to load upload queue: $e',
        name: 'UploadQueue',
      );
      _entries = [];
      _loaded = true;
    }
  }

  // ---------------------------------------------------------------------------
  // Queue mutations
  // ---------------------------------------------------------------------------

  /// Adds a new entry to the queue.
  ///
  /// Skips duplicates — same jobId + mediaId + mediaType already
  /// pending or uploading.
  Future<void> enqueue({
    required String jobId,
    required String jobDirPath,
    required String mediaId,
    required String mediaType,
  }) async {
    await _ensureLoaded();

    final isDuplicate = _entries.any(
      (e) =>
          e.jobId == jobId &&
          e.mediaId == mediaId &&
          e.mediaType == mediaType &&
          (e.isPending || e.isUploading),
    );
    if (isDuplicate) return;

    final entry = UploadQueueEntry(
      id: _uuid.v4(),
      jobId: jobId,
      jobDirPath: jobDirPath,
      mediaId: mediaId,
      mediaType: mediaType,
      status: 'pending',
      retryCount: 0,
      createdAt: DateTime.now().toUtc().toIso8601String(),
    );

    _entries.add(entry);
    await _save();

    developer.log(
      'Enqueued $mediaType $mediaId for job $jobId',
      name: 'UploadQueue',
    );

    onNewEntry?.call();
  }

  /// Returns the next eligible entry, or null if the queue is drained.
  ///
  /// When [isEligible] is provided, only entries that pass both the base
  /// processability check and the custom filter are returned. This is used
  /// by the background upload service to enforce exponential backoff timing.
  Future<UploadQueueEntry?> nextPending({
    bool Function(UploadQueueEntry)? isEligible,
  }) async {
    await _ensureLoaded();
    for (final entry in _entries) {
      if (!_isProcessable(entry)) continue;
      if (isEligible != null && !isEligible(entry)) continue;
      return entry;
    }
    return null;
  }

  Future<void> markUploading(String id) async {
    await _updateEntry(id, (e) => e.copyWith(
      status: 'uploading',
      lastAttempt: DateTime.now().toUtc().toIso8601String(),
    ));
  }

  Future<void> markCompleted(String id) async {
    await _updateEntry(id, (e) => e.copyWith(status: 'completed'));
  }

  Future<void> markFailed(String id) async {
    await _updateEntry(id, (e) => e.copyWith(
      status: 'failed',
      retryCount: e.retryCount + 1,
    ));
  }

  /// Removes all completed entries from the queue.
  Future<void> removeCompleted() async {
    await _ensureLoaded();
    final before = _entries.length;
    _entries.removeWhere((e) => e.isCompleted);
    if (_entries.length != before) await _save();
  }

  // ---------------------------------------------------------------------------
  // Queue processor
  // ---------------------------------------------------------------------------

  /// Processes the next eligible entry using [controller].
  ///
  /// When [isEligible] is provided, it filters which entries are considered
  /// ready for processing (e.g., respecting exponential backoff timing).
  ///
  /// Returns true if an entry was processed (success or failure),
  /// false if no eligible entries remain.
  Future<bool> processNext(
    UploadController controller, {
    bool Function(UploadQueueEntry)? isEligible,
  }) async {
    final entry = await nextPending(isEligible: isEligible);
    if (entry == null) return false;

    await markUploading(entry.id);
    final jobDir = Directory(entry.jobDirPath);

    try {
      final dynamic result;
      if (entry.isPhoto) {
        result = await controller.uploadPhoto(
          jobDir: jobDir,
          jobId: entry.jobId,
          photoId: entry.mediaId,
        );
      } else {
        result = await controller.uploadVideo(
          jobDir: jobDir,
          jobId: entry.jobId,
          videoId: entry.mediaId,
        );
      }

      if (result != null) {
        await markCompleted(entry.id);
        developer.log(
          'Upload completed: ${entry.mediaType} ${entry.mediaId}',
          name: 'UploadQueue',
        );
      } else {
        await markFailed(entry.id);
        developer.log(
          'Upload returned null: ${entry.mediaType} ${entry.mediaId} '
          '(attempt ${entry.retryCount + 1})',
          name: 'UploadQueue',
        );
      }
    } catch (e) {
      await markFailed(entry.id);
      developer.log(
        'Upload exception: ${entry.mediaType} ${entry.mediaId}: $e',
        name: 'UploadQueue',
      );
    }

    return true;
  }

  /// Processes all eligible entries sequentially.
  ///
  /// Returns the number of entries processed.
  Future<int> processAll(
    UploadController controller, {
    bool Function(UploadQueueEntry)? isEligible,
  }) async {
    var processed = 0;
    while (await processNext(controller, isEligible: isEligible)) {
      processed++;
    }
    return processed;
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  bool _isProcessable(UploadQueueEntry e) =>
      e.isPending || (e.isFailed && e.retryCount < maxRetries);

  Future<void> _ensureLoaded() async {
    if (!_loaded) await load();
  }

  Future<void> _updateEntry(
    String id,
    UploadQueueEntry Function(UploadQueueEntry) updater,
  ) async {
    await _ensureLoaded();
    for (var i = 0; i < _entries.length; i++) {
      if (_entries[i].id == id) {
        _entries[i] = updater(_entries[i]);
        await _save();
        return;
      }
    }
  }

  Future<void> _save() async {
    final file = await _queueFile();
    final dir = file.parent;
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    final json = jsonEncode(_entries.map((e) => e.toJson()).toList());
    await file.writeAsString(json, flush: true);
  }

  Future<File> _queueFile() async {
    final rootPath = await paths.getRootPath();
    return File('$rootPath/$_fileName');
  }
}
