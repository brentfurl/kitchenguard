import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'domain/models/app_role.dart';
import 'presentation/jobs_home.dart';
import 'presentation/screens/auth_screen.dart';
import 'providers/app_role_provider.dart';
import 'providers/auth_provider.dart';

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
      home: const _AuthGate(),
    );
  }
}

/// Root gate that routes to the appropriate screen based on auth and role state.
///
/// - Not authenticated → [AuthScreen]
/// - Authenticated, no role → role picker
/// - Authenticated, has role → [JobsHome]
class _AuthGate extends ConsumerStatefulWidget {
  const _AuthGate();

  @override
  ConsumerState<_AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<_AuthGate> {
  bool _claimsChecked = false;
  bool _checkingClaims = false;

  Future<void> _checkClaims() async {
    if (_checkingClaims) return;
    _checkingClaims = true;
    try {
      await ref.read(appRoleProvider.notifier).refreshFromClaims();
    } finally {
      if (mounted) {
        setState(() {
          _claimsChecked = true;
          _checkingClaims = false;
        });
      }
    }
  }

  Future<void> _onRoleSelected(AppRole role) async {
    setState(() => _checkingClaims = true);
    final roleNotifier = ref.read(appRoleProvider.notifier);
    try {
      // Persist locally first so the user can proceed immediately.
      await roleNotifier.setRoleLocal(role);

      // Hotfix: avoid iOS native crash path observed after role selection.
      // Role claim assignment can be completed from web/manager tooling.
      if (defaultTargetPlatform == TargetPlatform.iOS) return;

      await roleNotifier.setRole(role);
    } catch (_) {
      // Keep local role if remote claim assignment fails.
    } finally {
      if (mounted) setState(() => _checkingClaims = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final authAsync = ref.watch(authStateProvider);

    return authAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        body: Center(child: Text('Auth error: $e')),
      ),
      data: (user) {
        if (user == null) {
          _claimsChecked = false;
          return const AuthScreen();
        }

        if (!_claimsChecked) {
          _checkClaims();
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final role = ref.watch(appRoleProvider);

        if (role == null) {
          return _RolePickerScreen(
            isLoading: _checkingClaims,
            onRoleSelected: _onRoleSelected,
          );
        }

        return const JobsHome();
      },
    );
  }
}

/// Shown after sign-in when no role custom claim exists.
class _RolePickerScreen extends StatelessWidget {
  const _RolePickerScreen({
    required this.isLoading,
    required this.onRoleSelected,
  });

  final bool isLoading;
  final ValueChanged<AppRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.person_outline,
                    size: 64,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Select Your Role',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'How will you be using KitchenGuard?',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (isLoading)
                    const CircularProgressIndicator()
                  else ...[
                    _RoleCard(
                      icon: Icons.engineering_outlined,
                      title: 'Technician',
                      description:
                          'Capture photos, videos, and field notes during cleaning jobs.',
                      onTap: () => onRoleSelected(AppRole.technician),
                    ),
                    const SizedBox(height: 12),
                    _RoleCard(
                      icon: Icons.manage_accounts_outlined,
                      title: 'Manager',
                      description:
                          'Create and schedule jobs, manage crew, review documentation.',
                      onTap: () => onRoleSelected(AppRole.manager),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoleCard extends StatelessWidget {
  const _RoleCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outline),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(icon, size: 36, color: colorScheme.primary),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
