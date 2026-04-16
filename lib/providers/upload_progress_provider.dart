import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../application/jobs_service.dart';
import '../services/background_upload_service.dart';
import '../services/upload_controller.dart';
import '../services/upload_queue.dart';
import 'service_providers.dart';

/// Immutable snapshot of the upload queue's progress.
class UploadProgressState {
  const UploadProgressState({this.pendingCount = 0, this.isProcessing = false});

  /// Number of items waiting to be uploaded (pending + eligible retries).
  final int pendingCount;

  /// True while the queue processor is actively uploading.
  final bool isProcessing;

  bool get hasPending => pendingCount > 0;
  bool get isSynced => pendingCount == 0 && !isProcessing;
}

/// Manages upload queue processing and exposes progress state to the UI.
///
/// Automatically triggers processing when new items are enqueued (via
/// [UploadQueue.onNewEntry]) and on initialization. Also supports manual
/// triggering via [triggerUpload].
class UploadProgressNotifier extends StateNotifier<UploadProgressState> {
  UploadProgressNotifier({
    required this.queue,
    required this.uploadController,
    required this.jobsService,
  }) : super(const UploadProgressState()) {
    _init();
  }

  final UploadQueue queue;
  final UploadController? uploadController;
  final JobsService jobsService;
  bool _isProcessing = false;
  Timer? _retryTimer;

  static const _retryInterval = Duration(minutes: 3);

  Future<void> _init() async {
    queue.onNewEntry = _onNewEntry;
    _retryTimer = Timer.periodic(_retryInterval, (_) {
      if (!mounted) return;
      _processIfEligible();
    });
    try {
      await queue.load();
      await jobsService.enqueueUnsyncedMedia();
      _refreshState();
      await _processIfEligible();
    } catch (_) {
      // Best effort on init — queue may not exist yet
    }
  }

  void _onNewEntry() {
    if (!mounted) return;
    _refreshState();
    _processIfEligible();
  }

  void _refreshState() {
    if (!mounted) return;
    state = UploadProgressState(
      pendingCount: queue.pendingCount,
      isProcessing: _isProcessing,
    );
  }

  /// Manually triggers queue processing.
  ///
  /// No-op if already processing, not authenticated, or offline.
  Future<void> triggerUpload() async {
    await _processIfEligible();
  }

  Future<void> _processIfEligible() async {
    if (_isProcessing) return;
    if (uploadController == null) return;

    if (!await BackgroundUploadService.isConnected()) return;

    _isProcessing = true;
    _refreshState();

    try {
      while (mounted) {
        if (!await BackgroundUploadService.isConnected()) break;

        final didProcess = await queue.processNext(
          uploadController!,
          isEligible: BackgroundUploadService.isEligibleNow,
        );
        if (!didProcess) break;

        _refreshState();
      }

      await queue.removeCompleted();
    } finally {
      _isProcessing = false;
      _refreshState();
    }
  }

  @override
  void dispose() {
    queue.onNewEntry = null;
    _retryTimer?.cancel();
    super.dispose();
  }
}

/// Provides upload progress state and processing control to the UI.
///
/// Rebuilds when auth state changes (since [uploadControllerProvider]
/// depends on auth). When unauthenticated, the controller is null and
/// processing is skipped (items stay queued for later).
final uploadProgressProvider =
    StateNotifierProvider<UploadProgressNotifier, UploadProgressState>((ref) {
      final queue = ref.watch(uploadQueueProvider);
      final controller = ref.watch(uploadControllerProvider);
      final jobsService = ref.watch(jobsServiceProvider);
      return UploadProgressNotifier(
        queue: queue,
        uploadController: controller,
        jobsService: jobsService,
      );
    });
