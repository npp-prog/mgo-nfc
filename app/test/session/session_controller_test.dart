import 'package:flutter_test/flutter_test.dart';
import 'package:mgo_attendance/src/models/app_user.dart';
import 'package:mgo_attendance/src/router.dart';
import 'package:mgo_attendance/src/services/auth_repository.dart';
import 'package:mgo_attendance/src/session/session_controller.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeUserRepository users;
  late SessionController session;

  setUp(() {
    auth = FakeAuthRepository();
    users = FakeUserRepository();
    session = SessionController(auth: auth, users: users);
  });

  tearDown(() => session.dispose());

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('starts loading, then signed out when nobody is signed in', () async {
    final fresh = SessionController(auth: auth, users: users);
    addTearDown(fresh.dispose);
    expect(fresh.status, SessionStatus.loading);
    await settle();
    expect(fresh.status, SessionStatus.signedOut);
  });

  test('active employee becomes ready', () async {
    users.put(user(), uid: 'u1');
    auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
    await settle();
    expect(session.status, SessionStatus.ready);
    expect(session.user!.name, 'Juan dela Cruz');
    expect(session.isAdmin, isFalse);
  });

  test(
    'admin profile refreshes a stale token once to pick up the claim',
    () async {
      users.put(user(role: UserRole.admin), uid: 'u1');
      auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
      await settle();
      await settle();
      expect(session.status, SessionStatus.ready);
      expect(session.isAdmin, isTrue);
      expect(auth.forcedRefreshes, 1);
    },
  );

  test('admin with an up-to-date token is not refreshed', () async {
    auth.adminClaim = true;
    users.put(user(role: UserRole.admin), uid: 'u1');
    auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
    await settle();
    await settle();
    expect(auth.forcedRefreshes, 0);
  });

  test('missing profile and deactivated account are blocked', () async {
    users.put(null, uid: 'u1');
    auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
    await settle();
    expect(session.status, SessionStatus.blocked);
    expect(session.blockedReason, BlockedReason.noProfile);

    users.put(user(active: false), uid: 'u1');
    await settle();
    expect(session.blockedReason, BlockedReason.inactive);
  });

  test(
    'profile changes apply live: deactivation blocks, reactivation restores',
    () async {
      users.put(user(), uid: 'u1');
      auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
      await settle();
      expect(session.status, SessionStatus.ready);

      users.put(user(active: false), uid: 'u1');
      await settle();
      expect(session.status, SessionStatus.blocked);

      users.put(user(), uid: 'u1');
      await settle();
      expect(session.status, SessionStatus.ready);
    },
  );

  test('profile load error blocks with loadFailed', () async {
    auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
    await settle();
    users.fail('u1', Exception('permission-denied'));
    await settle();
    expect(session.status, SessionStatus.blocked);
    expect(session.blockedReason, BlockedReason.loadFailed);
  });

  test('sign out clears the user', () async {
    users.put(user(), uid: 'u1');
    auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
    await settle();
    await session.signOut();
    await settle();
    expect(session.status, SessionStatus.signedOut);
    expect(session.user, isNull);
  });

  group('redirectFor', () {
    test(
      'loading -> splash, signed out -> login, blocked -> blocked',
      () async {
        final fresh = SessionController(auth: auth, users: users);
        addTearDown(fresh.dispose);
        expect(redirectFor(fresh, Routes.home), Routes.splash);
        await settle();
        expect(redirectFor(session, Routes.admin), Routes.login);
        expect(redirectFor(session, Routes.login), isNull);

        users.put(user(active: false), uid: 'u1');
        auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
        await settle();
        expect(redirectFor(session, Routes.home), Routes.blocked);
      },
    );

    test('employee lands on home and cannot open admin pages', () async {
      users.put(user(), uid: 'u1');
      auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
      await settle();
      expect(redirectFor(session, Routes.login), Routes.home);
      expect(redirectFor(session, Routes.admin), Routes.home);
      expect(redirectFor(session, '${Routes.admin}/employees'), Routes.home);
      expect(redirectFor(session, Routes.home), isNull);
    });

    test('admin lands on admin and may also open home', () async {
      auth.adminClaim = true;
      users.put(user(role: UserRole.admin), uid: 'u1');
      auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
      await settle();
      await settle();
      expect(redirectFor(session, Routes.splash), Routes.admin);
      expect(redirectFor(session, Routes.admin), isNull);
      expect(redirectFor(session, Routes.home), isNull);
    });
  });
}
