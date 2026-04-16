import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:workmanager/workmanager.dart';

import '../data/repositories/cloud_job_repository.dart';
import '../data/repositories/local_job_repository.dart';
import '../domain/models/upload_queue_entry.dart';
import '../firebase_options.dart';
import '../storage/app_paths.dart';
import '../storage/atomic_write.dart';
import '../storage/image_file_store.dart';
import '../storage/job_scanner.dart';
import '../storage/job_store.dart';
import '../storage/video_file_store.dart';
import 'storage_service.dart';
import 'upload_controller.dart';
import 'upload_queue.dart';

/// Unique task name for the periodic background upload.
const String uploadQueueTaskName = 'com.kitchenguard.uploadQueue';

/// Orchestrates upload queue processing with connectivity checks and
/// exponential backoff for failed items.
///
/// Used by both the foreground [UploadProgressNotifier] and the
/// workmanager background callback.
class BackgroundUploadService {
  const BackgroundUploadService._();

  /// Computes the backoff duration for a given retry count.
  ///
  /// Schedule: 1 min, 2 min, 4 min, 8 min, 16 min, 30 min (cap).
  static Duration backoffFor(int retryCount) {
    if (retryCount <= 0) return Duration.zero;
    final seconds = math.min(math.pow(2, retryCount - 1).toInt() * 60, 30 * 60);
    return Duration(seconds: seconds);
  }

  /// Returns true if [entry] is eligible for processing right now,
  /// respecting exponential backoff for previously failed items.
  static bool isEligibleNow(UploadQueueEntry entry) {
    if (entry.isPending) return true;
    if (!entry.isFailed) return false;
    if (entry.retryCount >= UploadQueue.maxRetries) return false;
    if (entry.lastAttempt == null) return true;

    final lastAttempt = DateTime.parse(entry.lastAttempt!);
    final cooldown = backoffFor(entry.retryCount);
    return DateTime.now().toUtc().isAfter(lastAttempt.add(cooldown));
  }

  /// Returns true if the device has network connectivity.
  static Future<bool> isConnected() async {
    final result = await Connectivity().checkConnectivity();
    if (_hasUsableConnectivity(result) || await _hasInternetAccess()) {
      return true;
    }

    // Confirm once more to avoid transient false negatives on iOS.
    await Future<void>.delayed(const Duration(milliseconds: 1200));
    final confirmed = await Connectivity().checkConnectivity();
    return _hasUsableConnectivity(confirmed) || await _hasInternetAccess();
  }

  static bool _hasUsableConnectivity(List<ConnectivityResult> result) {
    return result.any((item) => item != ConnectivityResult.none);
  }

  static Future<bool> _hasInternetAccess() async {
    try {
      final lookup = await InternetAddress.lookup(
        'example.com',
      ).timeout(const Duration(seconds: 2));
      return lookup.isNotEmpty && lookup.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    }
  }

  /// Processes eligible queue entries with connectivity checks and backoff.
  ///
  /// Returns the number of items successfully uploaded.
  static Future<int> processQueue({
    required UploadQueue queue,
    required UploadController controller,
  }) async {
    if (!await isConnected()) return 0;

    var uploaded = 0;
    while (true) {
      if (!await isConnected()) break;

      final didProcess = await queue.processNext(
        controller,
        isEligible: isEligibleNow,
      );
      if (!didProcess) break;

      final lastEntry = queue.entries.lastWhere(
        (e) => e.isCompleted,
        orElse: () => queue.entries.first,
      );
      if (lastEntry.isCompleted) uploaded++;
    }

    await queue.removeCompleted();
    return uploaded;
  }
}

/// Top-level entry point for workmanager background execution.
///
/// Runs in a separate isolate — must re-initialize Firebase and build
/// its own service instances (no shared Riverpod state).
@pragma('vm:entry-point')
void uploadQueueCallbackDispatcher() {
  Workmanager().executeTask((taskName, inputData) async {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return true;

      final paths = AppPaths();
      final queue = UploadQueue(paths: paths);
      await queue.load();

      if (!queue.hasProcessableEntries) return true;

      if (!await BackgroundUploadService.isConnected()) return true;

      final storageService = StorageService();
      final jobStore = JobStore();
      final jobScanner = JobScanner(paths: paths, jobStore: jobStore);
      final imageStore = ImageFileStore(paths: paths);
      final videoStore = VideoFileStore(
        paths: paths,
        atomicWrite: atomicWriteBytes,
      );
      final localRepo = LocalJobRepository(
        paths: paths,
        jobStore: jobStore,
        jobScanner: jobScanner,
        imageStore: imageStore,
        videoStore: videoStore,
      );
      final jobRepo = CloudJobRepository(
        local: localRepo,
        firestore: FirebaseFirestore.instance,
        paths: paths,
      );
      final controller = UploadController(
        storageService: storageService,
        jobRepository: jobRepo,
        currentUserId: user.uid,
      );

      await BackgroundUploadService.processQueue(
        queue: queue,
        controller: controller,
      );

      return true;
    } catch (e, st) {
      developer.log(
        'Background upload task failed: $e',
        name: 'BackgroundUpload',
        error: e,
        stackTrace: st,
      );
      return true;
    }
  });
}
