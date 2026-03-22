import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models/app_role.dart';

/// Holds the current device role. `null` means not yet selected (first launch).
final appRoleProvider =
    StateNotifierProvider<AppRoleNotifier, AppRole?>((ref) {
  return AppRoleNotifier();
});

class AppRoleNotifier extends StateNotifier<AppRole?> {
  AppRoleNotifier() : super(null) {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(AppRole.prefsKey);
    state = AppRole.fromStorageString(stored);
  }

  Future<void> setRole(AppRole role) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(AppRole.prefsKey, role.toStorageString());
    state = role;
  }

  Future<void> clearRole() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(AppRole.prefsKey);
    state = null;
  }
}
