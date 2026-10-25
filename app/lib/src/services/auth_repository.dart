import 'package:firebase_auth/firebase_auth.dart';

/// Signed-in identity, independent of the Firebase SDK so it can be faked in tests.
class AuthIdentity {
  const AuthIdentity({required this.uid, required this.email});
  final String uid;
  final String? email;
}

/// Error shown to the user on the login screen.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract class AuthRepository {
  Stream<AuthIdentity?> authStateChanges();
  AuthIdentity? get currentIdentity;
  Future<void> signIn({required String email, required String password});
  Future<void> sendPasswordReset(String email);
  Future<void> signOut();

  /// Whether the ID token carries the `admin` claim. Pass [forceRefresh] after
  /// a role change so the new claim is picked up without signing out.
  Future<bool> hasAdminClaim({bool forceRefresh = false});
}

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);
  final FirebaseAuth _auth;

  static AuthIdentity? _toIdentity(User? u) =>
      u == null ? null : AuthIdentity(uid: u.uid, email: u.email);

  @override
  Stream<AuthIdentity?> authStateChanges() =>
      _auth.authStateChanges().map(_toIdentity);

  @override
  AuthIdentity? get currentIdentity => _toIdentity(_auth.currentUser);

  @override
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure(messageForAuthError(e.code));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (e) {
      // Don't reveal whether an account exists.
      if (e.code == 'user-not-found') return;
      throw AuthFailure(messageForAuthError(e.code));
    }
  }

  @override
  Future<void> signOut() => _auth.signOut();

  @override
  Future<bool> hasAdminClaim({bool forceRefresh = false}) async {
    final user = _auth.currentUser;
    if (user == null) return false;
    final token = await user.getIdTokenResult(forceRefresh);
    return token.claims?['admin'] == true;
  }
}

String messageForAuthError(String code) => switch (code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' ||
  'invalid-email' => 'Incorrect email or password.',
  'user-disabled' => 'This account has been deactivated. Contact your admin.',
  'too-many-requests' =>
    'Too many attempts. Please wait a moment and try again.',
  'network-request-failed' =>
    'No internet connection. Check your network and try again.',
  _ => 'Sign-in failed ($code). Please try again.',
};
