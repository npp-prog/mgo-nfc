import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/app_user.dart';
import '../services/auth_repository.dart';
import '../services/user_repository.dart';

enum SessionStatus {
  /// Waiting for Firebase Auth / the profile to load.
  loading,
  signedOut,

  /// Signed in with an active profile.
  ready,

  /// Signed in, but the account has no profile or is deactivated.
  blocked,
}

enum BlockedReason { noProfile, inactive, loadFailed }

/// Combines the auth state with the live `users/{uid}` profile and exposes a
/// single status for routing. Profile changes (deactivation, role change)
/// take effect immediately.
class SessionController extends ChangeNotifier {
  SessionController({required this._auth, required this._users}) {
    _authSub = _auth.authStateChanges().listen(_onAuthChanged);
  }

  final AuthRepository _auth;
  final UserRepository _users;
  StreamSubscription<AuthIdentity?>? _authSub;
  StreamSubscription<AppUser?>? _userSub;

  SessionStatus _status = SessionStatus.loading;
  AppUser? _user;
  BlockedReason? _blockedReason;
  bool _disposed = false;

  SessionStatus get status => _status;
  AppUser? get user => _user;
  BlockedReason? get blockedReason => _blockedReason;
  bool get isAdmin =>
      _status == SessionStatus.ready && (_user?.isAdmin ?? false);

  Future<void> signOut() => _auth.signOut();

  void _onAuthChanged(AuthIdentity? identity) {
    _userSub?.cancel();
    _userSub = null;
    _user = null;
    _blockedReason = null;
    if (identity == null) {
      _set(SessionStatus.signedOut);
      return;
    }
    _set(SessionStatus.loading);
    _userSub = _users
        .watchUser(identity.uid)
        .listen(
          _onProfile,
          onError: (Object e) {
            debugPrint('Failed to load profile: $e');
            _blockedReason = BlockedReason.loadFailed;
            _set(SessionStatus.blocked);
          },
        );
  }

  Future<void> _onProfile(AppUser? profile) async {
    final wasAdmin = _user?.isAdmin ?? false;
    _user = profile;
    if (profile == null) {
      _blockedReason = BlockedReason.noProfile;
      return _set(SessionStatus.blocked);
    }
    if (!profile.active) {
      _blockedReason = BlockedReason.inactive;
      return _set(SessionStatus.blocked);
    }
    _blockedReason = null;
    // Security rules use the token's admin claim. If the profile says admin
    // but the cached token predates the promotion, refresh it once.
    if (profile.isAdmin && !wasAdmin) {
      try {
        if (!await _auth.hasAdminClaim()) {
          await _auth.hasAdminClaim(forceRefresh: true);
        }
      } catch (e) {
        debugPrint('Token refresh failed: $e');
      }
      // Signed out or a newer profile arrived while refreshing.
      if (!identical(_user, profile)) return;
    }
    _set(SessionStatus.ready);
  }

  void _set(SessionStatus s) {
    if (_disposed) return;
    _status = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _authSub?.cancel();
    _userSub?.cancel();
    super.dispose();
  }
}
