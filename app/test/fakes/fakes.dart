import 'dart:async';

import 'package:mgo_attendance/src/models/app_user.dart';
import 'package:mgo_attendance/src/services/auth_repository.dart';
import 'package:mgo_attendance/src/services/user_repository.dart';

/// A value stream like Firestore/Auth snapshots: each new listener first gets
/// the current value (if any), then every later change. Nothing is dropped
/// when values are set before anyone listens.
class _Live<T> {
  final _listeners = <StreamController<T>>{};
  bool _hasValue = false;
  late T _value;

  T get value => _value;

  void set(T v) {
    _value = v;
    _hasValue = true;
    for (final c in _listeners) {
      c.add(v);
    }
  }

  void error(Object e) {
    for (final c in _listeners) {
      c.addError(e);
    }
  }

  Stream<T> stream() {
    late final StreamController<T> c;
    c = StreamController<T>(
      onListen: () {
        _listeners.add(c);
        if (_hasValue) c.add(_value);
      },
      onCancel: () => _listeners.remove(c),
    );
    return c.stream;
  }
}

class FakeAuthRepository implements AuthRepository {
  final _live = _Live<AuthIdentity?>()..set(null);

  /// Credentials that sign in successfully: email -> (password, uid).
  final accounts = <String, (String, String)>{};
  bool adminClaim = false;
  int forcedRefreshes = 0;
  final resetRequests = <String>[];
  Completer<void>? signInGate;

  void emit(AuthIdentity? identity) => _live.set(identity);

  @override
  Stream<AuthIdentity?> authStateChanges() => _live.stream();

  @override
  AuthIdentity? get currentIdentity => _live.value;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (signInGate != null) await signInGate!.future;
    final account = accounts[email.trim()];
    if (account == null || account.$1 != password) {
      throw AuthFailure(messageForAuthError('invalid-credential'));
    }
    emit(AuthIdentity(uid: account.$2, email: email.trim()));
  }

  @override
  Future<void> sendPasswordReset(String email) async =>
      resetRequests.add(email);

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<bool> hasAdminClaim({bool forceRefresh = false}) async {
    if (forceRefresh) forcedRefreshes++;
    return adminClaim;
  }
}

class FakeUserRepository implements UserRepository {
  final _docs = <String, _Live<AppUser?>>{};

  _Live<AppUser?> _doc(String uid) =>
      _docs.putIfAbsent(uid, _Live<AppUser?>.new);

  void put(AppUser? user, {required String uid}) => _doc(uid).set(user);

  void fail(String uid, Object error) => _doc(uid).error(error);

  @override
  Stream<AppUser?> watchUser(String uid) => _doc(uid).stream();
}

AppUser user({
  String uid = 'u1',
  UserRole role = UserRole.employee,
  bool active = true,
  String name = 'Juan dela Cruz',
}) => AppUser(
  uid: uid,
  email: '$uid@example.com',
  displayName: name,
  employeeId: 'EMP-$uid',
  role: role,
  active: active,
);
