import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/app_role.dart';
import '../services/auth_service.dart';
import 'auth_provider.dart';

/// Holds the current user role. `null` means not yet determined.
///
/// Primary source: Firebase ID token custom claims.
/// Fallback: per-user SharedPreferences cache (offline support).
final appRoleProvider =
    StateNotifierProvider<AppRoleNotifier, AppRole?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return AppRoleNotifier(authService: authService);
});

class AppRoleNotifier extends StateNotifier<AppRole?> {
  AppRoleNotifier({required AuthService authService})
      : _authService = authService,
        super(null);

  final AuthService _authService;

  String? get _currentUid => _authService.currentUser?.uid;

  /// Per-user prefs key so different Firebase accounts on the same device
  /// each get their own cached role.
  String _userPrefsKey(String uid) => '${AppRole.prefsKey}_$uid';

  /// Read the role from Firebase ID token claims, falling back to the
  /// per-user SharedPreferences cache.
  ///
  /// Call after sign-in or token refresh. Returns the resolved role.
  Future<AppRole?> refreshFromClaims() async {
    try {
      final role = await _authService.getRoleFromClaims();
      if (role != null) {
        await _cacheRole(role);
        state = role;
        return role;
      }
    } catch (_) {
      // Claims unavailable (offline, etc.) — fall through to cache.
    }

    // No claims — try per-user cache (offline fallback).
    final cached = await _loadCachedRole();
    state = cached;
    return cached;
  }

  /// Assign a role via Cloud Function custom claims, refresh the token,
  /// and update the local cache.
  Future<void> setRole(AppRole role, {String? uid}) async {
    await _authService.setRole(role: role, uid: uid);
    await _cacheRole(role);
    state = role;
  }

  /// Set the role locally only (no Cloud Function call).
  /// Used when the Cloud Function is not yet deployed.
  Future<void> setRoleLocal(AppRole role) async {
    await _cacheRole(role);
    state = role;
  }

  Future<void> clearRole() async {
    final uid = _currentUid;
    if (uid != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_userPrefsKey(uid));
    }
    state = null;
  }

  Future<AppRole?> _loadCachedRole() async {
    final uid = _currentUid;
    if (uid == null) return null;
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_userPrefsKey(uid));
    return AppRole.fromStorageString(stored);
  }

  Future<void> _cacheRole(AppRole role) async {
    final uid = _currentUid;
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_userPrefsKey(uid), role.toStorageString());
  }
}
