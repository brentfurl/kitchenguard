import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/app_role.dart';
import '../services/auth_service.dart';
import 'auth_provider.dart';

/// Holds the current user role. `null` means not yet determined.
///
/// Primary source: Firebase ID token custom claims.
/// Fallback: SharedPreferences cache (offline support).
final appRoleProvider =
    StateNotifierProvider<AppRoleNotifier, AppRole?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AppRoleNotifier(authService: authService);
});

class AppRoleNotifier extends StateNotifier<AppRole?> {
  AppRoleNotifier({required AuthService authService})
      : _authService = authService,
        super(null) {
    _loadCachedRole();
  }

  final AuthService _authService;

  /// Load the locally cached role for instant startup (especially offline).
  Future<void> _loadCachedRole() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(AppRole.prefsKey);
    if (state == null) {
      state = AppRole.fromStorageString(stored);
    }
  }

  /// Read the role from Firebase ID token claims and update the local cache.
  ///
  /// Call after sign-in or token refresh. Returns the resolved role.
  Future<AppRole?> refreshFromClaims() async {
    try {
      final role = await _authService.getRoleFromClaims();
      if (role != null) {
        await _cacheRole(role);
        state = role;
      }
      return role;
    } catch (_) {
      return state;
    }
  }

  /// Assign a role via Cloud Function custom claims, refresh the token,
  /// and update the local cache.
  Future<void> setRole(AppRole role, {String? uid}) async {
    await _authService.setRole(role: role, uid: uid);
    await _cacheRole(role);
    state = role;
  }

  /// Set the role locally only (no Cloud Function call).
  /// Used for offline fallback or during initial cache load.
  Future<void> setRoleLocal(AppRole role) async {
    await _cacheRole(role);
    state = role;
  }

  Future<void> clearRole() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppRole.prefsKey);
    state = null;
  }

  Future<void> _cacheRole(AppRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppRole.prefsKey, role.toStorageString());
  }
}
