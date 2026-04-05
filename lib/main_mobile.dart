import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

import 'services/background_upload_service.dart';

Future<void> initPlatform() async {
  try {
    await Workmanager().initialize(uploadQueueCallbackDispatcher);
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await Workmanager().registerPeriodicTask(
        uploadQueueTaskName,
        uploadQueueTaskName,
        frequency: const Duration(minutes: 20),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    } else {
      await Workmanager().registerPeriodicTask(
        'upload-queue-periodic',
        uploadQueueTaskName,
        frequency: const Duration(minutes: 15),
        constraints: Constraints(networkType: NetworkType.connected),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      );
    }
  } catch (e, st) {
    developer.log(
      'Workmanager init failed (background uploads disabled): $e',
      name: 'initPlatform',
      error: e,
      stackTrace: st,
    );
  }
}
