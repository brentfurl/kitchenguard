import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/models/app_role.dart';
import '../presentation/screens/auth_screen.dart';
import '../providers/app_role_provider.dart';
import '../providers/auth_provider.dart';
import 'web_dashboard.dart';

/// Root widget for the Flutter web build.
///
/// Named [KitchenGuardApp] to match the conditional export contract in
/// `app_entry.dart`. On web, this serves the management dashboard; on mobile,
/// the identically-named class in `app.dart` serves the field documentation
/// app.
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
      title: 'KitchenGuard Manager',
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
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
          contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        ),
        dataTableTheme: const DataTableThemeData(
          headingTextStyle: TextStyle(
            fontWeight: FontWeight.w600,
            color: textPrimary,
          ),
        ),
      ),
      home: const _WebAuthGate(),
    );
  }
}

/// Auth gate for the web dashboard.
///
/// Routes to [AuthScreen] when signed out, then checks the user's role.
/// Only managers are permitted on the web dashboard; technicians see a
/// "not authorized" message.
class _WebAuthGate extends ConsumerStatefulWidget {
  const _WebAuthGate();

  @override
  ConsumerState<_WebAuthGate> createState() => _WebAuthGateState();
}

class _WebAuthGateState extends ConsumerState<_WebAuthGate> {
  bool _claimsChecked = false;
  bool _checkingClaims = false;

  Future<void> _checkClaims() async {
    if (_checkingClaims) return;
    _checkingClaims = true;
    try {
      await ref.read(appRoleProvider.notifier).refreshFromClaims();
      // Fire-and-forget — don't block auth flow on Firestore write.
      _ensureUserDoc();
    } finally {
      if (mounted) {
        setState(() {
          _claimsChecked = true;
          _checkingClaims = false;
        });
      }
    }
  }

  /// Write/update the current user's profile in the `users` collection so the
  /// user management screen has a record of all users.
  Future<void> _ensureUserDoc() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'email': user.email,
        'displayName': user.displayName ?? user.email?.split('@').first,
        'lastLoginAt': DateTime.now().toUtc().toIso8601String(),
      }, SetOptions(merge: true));
    } catch (_) {
      // Non-critical — user doc creation may fail offline.
    }
  }

  Future<void> _onRoleSelected(AppRole role) async {
    setState(() => _checkingClaims = true);
    try {
      await ref.read(appRoleProvider.notifier).setRole(role);
      await _ensureUserDoc();
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'role': role.toStorageString(),
        }, SetOptions(merge: true));
      }
    } catch (_) {
      await ref.read(appRoleProvider.notifier).setRoleLocal(role);
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
          return _WebRolePickerScreen(
            isLoading: _checkingClaims,
            onRoleSelected: _onRoleSelected,
          );
        }

        if (role != AppRole.manager) {
          return _NotAuthorizedScreen(
            onSignOut: () async {
              await ref.read(appRoleProvider.notifier).clearRole();
              await ref.read(authServiceProvider).signOut();
            },
          );
        }

        return const WebDashboard();
      },
    );
  }
}

class _WebRolePickerScreen extends StatelessWidget {
  const _WebRolePickerScreen({
    required this.isLoading,
    required this.onRoleSelected,
  });

  final bool isLoading;
  final ValueChanged<AppRole> onRoleSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_outline, size: 64, color: cs.primary),
              const SizedBox(height: 16),
              Text('Select Your Role',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('How will you be using KitchenGuard?',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 32),
              if (isLoading)
                const CircularProgressIndicator()
              else ...[
                _roleCard(
                  context,
                  icon: Icons.manage_accounts_outlined,
                  title: 'Manager',
                  desc:
                      'Create and schedule jobs, manage crew, review documentation.',
                  onTap: () => onRoleSelected(AppRole.manager),
                ),
                const SizedBox(height: 12),
                _roleCard(
                  context,
                  icon: Icons.engineering_outlined,
                  title: 'Technician',
                  desc:
                      'Capture photos, videos, and field notes during cleaning jobs.',
                  onTap: () => onRoleSelected(AppRole.technician),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _roleCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String desc,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outline),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(children: [
            Icon(icon, size: 36, color: cs.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(desc,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
          ]),
        ),
      ),
    );
  }
}

class _NotAuthorizedScreen extends StatelessWidget {
  const _NotAuthorizedScreen({required this.onSignOut});

  final VoidCallback onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.block, size: 64, color: cs.error),
              const SizedBox(height: 16),
              Text('Access Restricted',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text(
                'The web dashboard is available to managers only. '
                'Please use the mobile app for field documentation.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 24),
              OutlinedButton.icon(
                onPressed: onSignOut,
                icon: const Icon(Icons.logout),
                label: const Text('Sign Out'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
