import 'package:flutter/material.dart';

import 'application/jobs_service.dart';
import 'application/startup_service.dart';
import 'presentation/jobs_home.dart';
import 'storage/app_paths.dart';
import 'storage/atomic_write.dart';
import 'storage/day_note_store.dart';
import 'storage/image_file_store.dart';
import 'storage/job_scanner.dart';
import 'storage/job_store.dart';
import 'storage/video_file_store.dart';

class KitchenGuardApp extends StatelessWidget {
  const KitchenGuardApp({super.key});

  @override
  Widget build(BuildContext context) {
    const primaryGreen = Color(0xFF2F7A2F);
    const accentGreen = Color(0xFF4CAF50);
    const backgroundNeutral = Color(0xFFF5F5F5);
    const surfaceNeutral = Color(0xFFFFFFFF);
    const surfaceVariantNeutral = Color(0xFFF2F2F2);
    const outlineNeutral = Color(0xFFD3D7DA);
    const textPrimary = Color(0xFF1C1F1C);
    const textSecondary = Color(0xFF4E5550);

    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: primaryGreen,
      onPrimary: Colors.white,
      primaryContainer: Color(0xFFDCEFD9),
      onPrimaryContainer: Color(0xFF123012),
      secondary: accentGreen,
      onSecondary: Colors.white,
      secondaryContainer: Color(0xFFE2F4E0),
      onSecondaryContainer: Color(0xFF163A16),
      tertiary: Color(0xFF7B8794),
      onTertiary: Colors.white,
      tertiaryContainer: Color(0xFFE8ECEF),
      onTertiaryContainer: Color(0xFF2A3138),
      error: Color(0xFFB3261E),
      onError: Colors.white,
      errorContainer: Color(0xFFF9DEDC),
      onErrorContainer: Color(0xFF410E0B),
      surface: surfaceNeutral,
      onSurface: textPrimary,
      surfaceContainerHighest: surfaceVariantNeutral,
      onSurfaceVariant: textSecondary,
      outline: outlineNeutral,
      outlineVariant: Color(0xFFE3E6E8),
      shadow: Color(0x33000000),
      scrim: Color(0x80000000),
      inverseSurface: Color(0xFF2A2F2A),
      onInverseSurface: Color(0xFFF1F3F1),
      inversePrimary: Color(0xFFA6D4A3),
      surfaceTint: primaryGreen,
    );

    final paths = AppPaths();
    final jobStore = JobStore();
    final imageStore = ImageFileStore(paths: paths);
    final videoStore = VideoFileStore(
      paths: paths,
      atomicWrite: atomicWriteBytes,
    );
    final dayNoteStore = DayNoteStore(paths: paths);
    final scanner = JobScanner(paths: paths, jobStore: jobStore);
    final startup = StartupService(scanner: scanner);
    final jobs = JobsService(
      paths: paths,
      jobStore: jobStore,
      imageStore: imageStore,
      videoStore: videoStore,
      dayNoteStore: dayNoteStore,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: colorScheme,
        scaffoldBackgroundColor: backgroundNeutral,
        appBarTheme: const AppBarTheme(
          backgroundColor: surfaceNeutral,
          foregroundColor: textPrimary,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 1,
        ),
        cardTheme: const CardThemeData(
          color: surfaceNeutral,
          surfaceTintColor: Colors.transparent,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: primaryGreen,
          foregroundColor: Colors.white,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: primaryGreen,
            foregroundColor: Colors.white,
            disabledBackgroundColor: primaryGreen.withValues(alpha: 0.22),
            disabledForegroundColor: Colors.white.withValues(alpha: 0.68),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: primaryGreen,
            side: const BorderSide(color: outlineNeutral),
          ),
        ),
        chipTheme: ChipThemeData.fromDefaults(
          secondaryColor: accentGreen,
          brightness: Brightness.light,
          labelStyle: const TextStyle(color: textPrimary),
        ),
      ),
      home: JobsHome(startup: startup, jobs: jobs),
    );
  }
}
