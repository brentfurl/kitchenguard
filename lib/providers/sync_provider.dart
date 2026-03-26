import 'dart:async';
import 'dart:developer' as developer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    this.lastPullTime,
    this.uploadPending = 0,
    this.isUploading = false,
  });

  final bool isOnline;
  final bool isPulling;
  final DateTime? lastPullTime;
  final int uploadPending;
  final bool isUploading;

  bool get isSynced => !isPulling && !isUploading && uploadPending == 0;
  bool get hasActivity => isPulling || isUploading;

  SyncState copyWith({
    bool? isOnline,
    bool? isPulling,
    DateTime? lastPullTime,
    int? uploadPending,
    bool? isUploading,
  }) {
    return SyncState(
      isOnline: isOnline ?? this.isOnline,
      isPulling: isPulling ?? this.isPulling,
      lastPullTime: lastPullTime ?? this.lastPullTime,
      uploadPending: uploadPending ?? this.uploadPending,
      isUploading: isUploading ?? this.isUploading,
    );
  }
}

/// Coordinates pull (Firestore → local) and monitors connectivity.
///
/// - Auto-pulls on initialization (app open)
/// - Runs a periodic pull every [_pullInterval] when online
/// - Monitors connectivity changes and triggers pull on reconnect
/// - Merges upload progress state from [uploadProgressProvider]
class SyncNotifier extends StateNotifier<SyncState> {
  SyncNotifier({
    required this.ref,
  }) : super(const SyncState()) {
    _init();
  }

  final Ref ref;
  Timer? _periodicTimer;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _hasCompletedInitialPull = false;

  static const _pullInterval = Duration(minutes: 5);

  void _init() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen(
      _onConnectivityChanged,
    );

    Connectivity().checkConnectivity().then((results) {
      final online = !results.contains(ConnectivityResult.none);
      state = state.copyWith(isOnline: online);
      if (online) _initialPull();
    });
  }

  void _onConnectivityChanged(List<ConnectivityResult> results) {
    final online = !results.contains(ConnectivityResult.none);
    final wasOffline = !state.isOnline;
    state = state.copyWith(isOnline: online);

    if (online && wasOffline) {
      pullNow();
    }
  }

  Future<void> _initialPull() async {
    if (_hasCompletedInitialPull) return;
    _hasCompletedInitialPull = true;
    await pullNow();
    _startPeriodicPull();
  }

  void _startPeriodicPull() {
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(_pullInterval, (_) {
      if (state.isOnline && !state.isPulling) {
        pullNow();
      }
    });
  }

  /// Triggers an immediate Firestore pull and job list reload.
  ///
  /// After a successful pull, bumps [pullVersionProvider] so that any
  /// active [jobDetailProvider] instances rebuild with the merged data.
  Future<void> pullNow() async {
    if (state.isPulling) return;
    if (!state.isOnline) return;

    state = state.copyWith(isPulling: true);
    try {
      await ref.read(jobRepositoryProvider).pullFromCloud();
      await ref.read(jobListProvider.notifier).reload();
      ref.read(pullVersionProvider.notifier).state++;
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
    }
  }

  /// Updates upload-side state from [UploadProgressState].
  void updateUploadState(UploadProgressState uploadState) {
    state = state.copyWith(
      uploadPending: uploadState.pendingCount,
      isUploading: uploadState.isProcessing,
    );
  }

  @override
  void dispose() {
    _periodicTimer?.cancel();
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
