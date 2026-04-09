import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/day_note.dart';
import '../domain/models/job.dart';
import 'day_notes_provider.dart';
import 'day_schedule_provider.dart';
import 'job_list_provider.dart';
import 'repository_providers.dart';
import 'upload_progress_provider.dart';

/// Incremented after every successful pull so that family providers
/// (e.g. [jobDetailProvider]) that watch it automatically rebuild
/// with the freshly merged data.
final pullVersionProvider = StateProvider<int>((_) => 0);

/// Combined sync state exposed to the UI.
///
/// Tracks both the Firestore pull side (scheduling data) and the
/// Firebase Storage push side (media uploads).
class SyncState {
  const SyncState({
    this.isOnline = true,
    this.isPulling = false,
    this.isListening = false,
    this.lastPullTime,
    this.uploadPending = 0,
    this.isUploading = false,
  });

  final bool isOnline;
  final bool isPulling;

  /// True while the Firestore real-time listener is active.
  final bool isListening;
  final DateTime? lastPullTime;
  final int uploadPending;
  final bool isUploading;

  bool get isSynced =>
      !isPulling && !isUploading && uploadPending == 0 && isListening;
  bool get hasActivity => isPulling || isUploading;

  SyncState copyWith({
    bool? isOnline,
    bool? isPulling,
    bool? isListening,
    DateTime? lastPullTime,
    int? uploadPending,
    bool? isUploading,
  }) {
    return SyncState(
      isOnline: isOnline ?? this.isOnline,
      isPulling: isPulling ?? this.isPulling,
      isListening: isListening ?? this.isListening,
      lastPullTime: lastPullTime ?? this.lastPullTime,
      uploadPending: uploadPending ?? this.uploadPending,
      isUploading: isUploading ?? this.isUploading,
    );
  }
}

/// Coordinates real-time Firestore sync and monitors connectivity.
///
/// Phase 7 upgrade: replaced 5-minute polling with Firestore `.snapshots()`
/// real-time listener. Changes from any device now appear within seconds.
///
/// - Subscribes to the Firestore `jobs` collection stream on init
/// - Debounces rapid snapshot events (1 second) to batch filesystem I/O
/// - Monitors connectivity changes for the offline banner
/// - Keeps [pullNow] for manual sync triggers (pull-to-refresh, tap)
/// - Merges upload progress state from [uploadProgressProvider]
class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier({
    required this.ref,
  }) : super(const SyncState()) {
    _init();
  }

  final Ref ref;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  StreamSubscription<List<Job>>? _cloudJobsSub;
  StreamSubscription<Map<String, List<DayNote>>>? _dayNotesSub;
  StreamSubscription<Map<String, dynamic>>? _daySchedulesSub;
  Timer? _debounceTimer;
  List<Job>? _pendingCloudJobs;
  bool _isMerging = false;

  static const _debounceDelay = Duration(seconds: 1);

  void _init() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    Connectivity().checkConnectivity().then((results) {
      final online = !results.contains(ConnectivityResult.none);
      state = state.copyWith(isOnline: online);
      _subscribeToCloudJobs();
      _subscribeToDayNotes();
      _subscribeToDaySchedules();
    });
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final wasOffline = !state.isOnline;
    final online = !results.contains(ConnectivityResult.none);
    state = state.copyWith(isOnline: online);

    if (online && wasOffline) {
      ref.read(uploadProgressProvider.notifier).triggerUpload();
    }
  }

  // ---------------------------------------------------------------------------
  // Real-time Firestore listener
  // ---------------------------------------------------------------------------

  void _subscribeToCloudJobs() {
    _cloudJobsSub?.cancel();

    final stream = ref.read(jobRepositoryProvider).watchCloudJobs();
    if (stream == null) {
      developer.log(
        'Repository does not support cloud watch — skipping listener',
        name: 'SyncNotifier',
      );
      return;
    }

    state = state.copyWith(isListening: true);
    _cloudJobsSub = stream.listen(
      _onCloudSnapshot,
      onError: (Object e, StackTrace st) {
        developer.log(
          'Cloud jobs stream error: $e',
          name: 'SyncNotifier',
          error: e,
          stackTrace: st,
        );
      },
    );
  }

  /// Debounces incoming snapshots so rapid writes (e.g. manager creating
  /// several jobs) are batched into a single merge + UI refresh.
  void _onCloudSnapshot(List<Job> cloudJobs) {
    _pendingCloudJobs = cloudJobs;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(_debounceDelay, _processPendingSnapshot);
  }

  Future<void> _processPendingSnapshot() async {
    final jobs = _pendingCloudJobs;
    if (jobs == null) return;

    if (_isMerging) return;

    _pendingCloudJobs = null;
    _isMerging = true;
    state = state.copyWith(isPulling: true);

    try {
      final repo = ref.read(jobRepositoryProvider);
      await repo.mergeCloudJobs(jobs);
      await ref.read(jobListProvider.notifier).reload();
      ref.read(pullVersionProvider.notifier).state++;
      ref.invalidate(dayScheduleProvider);
      state = state.copyWith(
        isPulling: false,
        lastPullTime: DateTime.now(),
      );
    } catch (e, st) {
      developer.log(
        'Real-time merge failed: $e',
        name: 'SyncNotifier',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(isPulling: false);
    } finally {
      _isMerging = false;
      if (_pendingCloudJobs != null) {
        _processPendingSnapshot();
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Real-time DayNotes listener
  // ---------------------------------------------------------------------------

  void _subscribeToDayNotes() {
    _dayNotesSub?.cancel();

    final stream = ref.read(dayNoteRepositoryProvider).watchAll();
    if (stream == null) return;

    _dayNotesSub = stream.listen(
      (_) {
        ref.invalidate(dayNotesProvider);
      },
      onError: (Object e, StackTrace st) {
        developer.log(
          'Day notes stream error: $e',
          name: 'SyncNotifier',
          error: e,
          stackTrace: st,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Real-time DaySchedules listener
  // ---------------------------------------------------------------------------

  void _subscribeToDaySchedules() {
    _daySchedulesSub?.cancel();

    final stream = ref.read(dayScheduleRepositoryProvider).watchAll();
    if (stream == null) return;

    _daySchedulesSub = stream.listen(
      (_) {
        ref.invalidate(dayScheduleProvider);
      },
      onError: (Object e, StackTrace st) {
        developer.log(
          'Day schedules stream error: $e',
          name: 'SyncNotifier',
          error: e,
          stackTrace: st,
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // Manual pull (pull-to-refresh, tap sync indicator)
  // ---------------------------------------------------------------------------

  /// Triggers an immediate Firestore fetch-and-merge.
  ///
  /// After a successful pull, bumps [pullVersionProvider] so that any
  /// active [jobDetailProvider] instances rebuild with the merged data.
  Future<void> pullNow() async {
    if (_isMerging) return;
    if (!state.isOnline) return;

    _isMerging = true;
    state = state.copyWith(isPulling: true);
    try {
      await ref.read(jobRepositoryProvider).pullFromCloud();
      await ref.read(jobListProvider.notifier).reload();
      ref.read(pullVersionProvider.notifier).state++;
      ref.invalidate(dayScheduleProvider);
      state = state.copyWith(
        isPulling: false,
        lastPullTime: DateTime.now(),
      );
    } catch (e, st) {
      developer.log(
        'Pull failed: $e',
        name: 'SyncNotifier',
        error: e,
        stackTrace: st,
      );
      state = state.copyWith(isPulling: false);
    } finally {
      _isMerging = false;
    }
  }

  // ---------------------------------------------------------------------------
  // Upload state bridge
  // ---------------------------------------------------------------------------

  /// Updates upload-side state from [UploadProgressState].
  void updateUploadState(UploadProgressState uploadState) {
    state = state.copyWith(
      uploadPending: uploadState.pendingCount,
      isUploading: uploadState.isProcessing,
    );
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _cloudJobsSub?.cancel();
    _dayNotesSub?.cancel();
    _daySchedulesSub?.cancel();
    _connectivitySub?.cancel();
    super.dispose();
  }
}

/// Combined sync state provider.
///
/// Merges Firestore pull status with upload queue progress.
final syncProvider = StateNotifierProvider<SyncNotifier, SyncState>((ref) {
  final notifier = SyncNotifier(ref: ref);

  ref.listen<UploadProgressState>(uploadProgressProvider, (_, uploadState) {
    notifier.updateUploadState(uploadState);
  });

  final currentUpload = ref.read(uploadProgressProvider);
  notifier.updateUploadState(currentUpload);

  return notifier;
});
