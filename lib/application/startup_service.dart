import '../storage/job_scanner.dart';

/// Simple startup wrapper used by UI-facing layers.
class StartupService {
  StartupService({required this.scanner});

  final JobScanner scanner;

  Future<List<JobScanResult>> loadJobs() async {
    try {
      return await scanner.scanJobs();
    } catch (error) {
      throw StateError('Failed to load jobs during startup: $error');
    }
  }
}
