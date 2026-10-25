import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mgo_attendance/src/app.dart';
import 'package:mgo_attendance/src/app_scope.dart';
import 'package:mgo_attendance/src/models/app_user.dart';
import 'package:mgo_attendance/src/session/session_controller.dart';

import '../fakes/fakes.dart';

void main() {
  late FakeAuthRepository auth;
  late FakeUserRepository users;
  late SessionController session;

  setUp(() {
    auth = FakeAuthRepository()
      ..accounts['juan@example.com'] = ('password123', 'u1')
      ..accounts['boss@example.com'] = ('password123', 'boss');
    users = FakeUserRepository()
      ..put(user(), uid: 'u1')
      ..put(
        user(uid: 'boss', role: UserRole.admin, name: 'Boss'),
        uid: 'boss',
      )
      ..put(user(uid: 'gone', active: false), uid: 'gone');
  });

  // Created inside each test so its stream callbacks run in the test's fake-async zone.
  Future<void> pumpApp(WidgetTester tester) async {
    session = SessionController(auth: auth, users: users);
    addTearDown(session.dispose);
    await tester.pumpWidget(
      MgoAttendanceApp(
        services: AppServices(auth: auth, session: session),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> signIn(
    WidgetTester tester,
    String email,
    String password,
  ) async {
    await tester.enterText(find.byKey(const Key('login-email')), email);
    await tester.enterText(find.byKey(const Key('login-password')), password);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
  }

  testWidgets('shows login when signed out', (tester) async {
    await pumpApp(tester);
    expect(find.text('MGO Attendance'), findsOneWidget);
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('validates fields before calling sign-in', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pumpAndSettle();
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('Enter your password'), findsOneWidget);
  });

  testWidgets('wrong password shows a friendly error', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'juan@example.com', 'nope');
    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(session.status, SessionStatus.signedOut);
  });

  testWidgets('button is disabled while signing in', (tester) async {
    auth.signInGate = Completer<void>();
    await pumpApp(tester);
    await tester.enterText(
      find.byKey(const Key('login-email')),
      'juan@example.com',
    );
    await tester.enterText(
      find.byKey(const Key('login-password')),
      'password123',
    );
    await tester.tap(find.byKey(const Key('login-submit')));
    await tester.pump();
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('login-submit')),
    );
    expect(button.onPressed, isNull);
    auth.signInGate!.complete();
    await tester.pumpAndSettle();
  });

  testWidgets('employee signs in to the employee home and can sign out', (
    tester,
  ) async {
    await pumpApp(tester);
    await signIn(tester, 'juan@example.com', 'password123');
    expect(find.text('Hello, Juan dela Cruz'), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Sign out'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-submit')), findsOneWidget);
  });

  testWidgets('admin signs in to the admin home', (tester) async {
    await pumpApp(tester);
    await signIn(tester, 'boss@example.com', 'password123');
    expect(find.text('Admin'), findsOneWidget);
    expect(find.text('Employees'), findsOneWidget);
  });

  testWidgets('deactivated account sees the blocked screen', (tester) async {
    auth.accounts['gone@example.com'] = ('password123', 'gone');
    await pumpApp(tester);
    await signIn(tester, 'gone@example.com', 'password123');
    expect(find.textContaining('deactivated'), findsOneWidget);
  });

  testWidgets(
    'employee is kicked to the blocked screen when deactivated mid-session',
    (tester) async {
      await pumpApp(tester);
      await signIn(tester, 'juan@example.com', 'password123');
      users.put(user(active: false), uid: 'u1');
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('blocked-message')), findsOneWidget);
    },
  );

  testWidgets('forgot password needs an email, then sends a reset', (
    tester,
  ) async {
    await pumpApp(tester);
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('login-error')), findsOneWidget);

    await tester.enterText(
      find.byKey(const Key('login-email')),
      'juan@example.com',
    );
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();
    expect(auth.resetRequests, ['juan@example.com']);
    expect(find.textContaining('reset link'), findsOneWidget);
  });
}
