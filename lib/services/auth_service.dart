import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/models/app_role.dart';

/// Thin wrapper around [FirebaseAuth] and Cloud Functions for auth operations.
///
/// Exposes email/password sign-in, registration, sign-out, auth state stream,
/// and role management via custom claims.
class AuthService {
  AuthService({
    FirebaseAuth? auth,
    FirebaseFunctions? functions,
  })  : _auth = auth ?? FirebaseAuth.instance,
        _functions = functions ?? FirebaseFunctions.instance;

  final FirebaseAuth _auth;
  final FirebaseFunctions _functions;

  /// Current authenticated user, or null.
  User? get currentUser => _auth.currentUser;

  /// Stream of auth state changes (sign-in / sign-out).
  Stream<User?> authStateChanges() => _auth.authStateChanges();

  /// Sign in with email and password.
  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) {
    return _auth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Create a new account with email and password.
  Future<UserCredential> register({
    required String email,
    required String password,
  }) {
    return _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
  }

  /// Sign out the current user.
  Future<void> signOut() => _auth.signOut();

  /// Read the role from the current user's ID token custom claims.
  ///
  /// Returns null if not authenticated or no role claim exists.
  Future<AppRole?> getRoleFromClaims() async {
    final user = _auth.currentUser;
    if (user == null) return null;

    final tokenResult = await user.getIdTokenResult();
    final claims = tokenResult.claims;
    if (claims == null) return null;

    final roleString = claims['role'] as String?;
    return AppRole.fromStorageString(roleString);
  }

  /// Call the `setUserRole` Cloud Function to assign a role via custom claims.
  ///
  /// [uid] defaults to the current user (self-assignment).
  /// [role] must be a valid [AppRole].
  Future<void> setRole({
    required AppRole role,
    String? uid,
  }) async {
    final targetUid = uid ?? _auth.currentUser?.uid;
    if (targetUid == null) {
      throw StateError('No authenticated user and no uid provided');
    }

    final callable = _functions.httpsCallable('setUserRole');
    await callable.call<dynamic>({
      'uid': targetUid,
      'role': role.toStorageString(),
    });

    // Force token refresh to pick up the new custom claim.
    await _auth.currentUser?.getIdToken(true);
  }
}
