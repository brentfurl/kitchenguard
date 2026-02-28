import 'package:flutter/material.dart';

import 'application/jobs_service.dart';
import 'application/startup_service.dart';
import 'presentation/jobs_home.dart';
import 'storage/app_paths.dart';
import 'storage/atomic_write.dart';
import 'storage/image_file_store.dart';
import 'storage/job_scanner.dart';
import 'storage/job_store.dart';
import 'storage/video_file_store.dart';

class KitchenGuardApp extends StatelessWidget {
  const KitchenGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    final paths = AppPaths();
    final jobStore = JobStore();
    final imageStore = ImageFileStore(paths: paths);
    final videoStore = VideoFileStore(
      paths: paths,
      atomicWrite: atomicWriteBytes,
    );
    final scanner = JobScanner(paths: paths, jobStore: jobStore);
    final startup = StartupService(scanner: scanner);
    final jobs = JobsService(
      paths: paths,
      jobStore: jobStore,
      imageStore: imageStore,
      videoStore: videoStore,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: JobsHome(startup: startup, jobs: jobs),
    );
  }
}
