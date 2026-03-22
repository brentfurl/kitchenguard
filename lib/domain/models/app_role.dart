/// Device-level role setting.
///
/// Determines the default view emphasis. No feature locking — both roles
/// can access all features. Phase 4 connects this to Firebase Auth claims.
enum AppRole {
  manager,
  technician;

  /// Persistence key stored in SharedPreferences.
  static const _prefsKey = 'app_role';

  String get label {
    switch (this) {
      case AppRole.manager:
        return 'Manager';
      case AppRole.technician:
        return 'Technician';
    }
  }

  String toStorageString() => name;

  static AppRole? fromStorageString(String? value) {
    if (value == null) return null;
    for (final role in AppRole.values) {
      if (role.name == value) return role;
    }
    return null;
  }

  static String get prefsKey => _prefsKey;
}
