import 'package:workmanager/workmanager.dart';

import 'services/background_upload_service.dart';

Future<void> initPlatform() async {
  await Workmanager().initialize(uploadQueueCallbackDispatcher);
  await Workmanager().registerPeriodicTask(
    'upload-queue-periodic',
    uploadQueueTaskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}
