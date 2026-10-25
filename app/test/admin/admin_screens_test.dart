import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:mgo_attendance/src/app.dart';
import 'package:mgo_attendance/src/models/app_user.dart';
import 'package:mgo_attendance/src/models/day_summary.dart';
import 'package:mgo_attendance/src/router.dart';
import 'package:mgo_attendance/src/services/admin_repository.dart';
import 'package:mgo_attendance/src/services/auth_repository.dart';
import 'package:mgo_attendance/src/session/session_controller.dart';

import '../fakes/fakes.dart';

/// Scrolls the lazily built form until the field with [key] is built, then
/// brings it fully on screen so taps land on it.
Future<void> reveal(WidgetTester tester, String key) async {
  final finder = find.byKey(Key(key));
  await tester.scrollUntilVisible(
    finder,
    150,
    scrollable: find
        .descendant(of: find.byType(Form), matching: find.byType(Scrollable))
        .first,
  );
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

void main() {
  late FakeAuthRepository auth;
  late FakeUserRepository users;
  late FakeAdminRepository admin;

  final boss = user(
    uid: 'boss',
    name: 'Boss',
    role: UserRole.admin,
    trackAttendance: false,
  );
  final ana = user(uid: 'ana', name: 'Ana Cruz');
  final ben = user(uid: 'ben', name: 'Ben Reyes');
  final gone = user(uid: 'gone', name: 'Gone Away', active: false);

  setUp(() {
    auth = FakeAuthRepository()..adminClaim = true;
    users = FakeUserRepository()..put(boss, uid: 'boss');
    admin = FakeAdminRepository()..users.set([ana, ben, boss, gone]);
  });

  Future<void> pumpAdminAt(WidgetTester tester, String location) async {
    final session = SessionController(auth: auth, users: users);
    addTearDown(session.dispose);
    auth.emit(const AuthIdentity(uid: 'boss', email: 'boss@example.com'));
    await tester.pumpWidget(
      MgoAttendanceApp(
        services: testServices(auth: auth, session: session, admin: admin),
      ),
    );
    await tester.pumpAndSettle();
    final ctx = tester.element(find.byType(Scaffold).first);
    GoRouter.of(ctx).push(location);
    await tester.pumpAndSettle();
  }

  group('dashboard', () {
    testWidgets('shows counts and people for today, live', (tester) async {
      final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
      final now = DateTime.now();
      final isWorkDay = now.weekday <= 5;
      admin.setDay(today, [
        DaySummary(
          userId: 'ana',
          date: today,
          firstIn: DateTime(now.year, now.month, now.day, 7, 55),
          lastIsIn: true,
          tapCount: 1,
        ),
      ]);
      await pumpAdminAt(tester, Routes.dashboard);

      String count(String key) => (tester.widget<Text>(
        find
            .descendant(of: find.byKey(Key(key)), matching: find.byType(Text))
            .first,
      )).data!;
      expect(count('count-present'), '1');
      expect(count('count-in'), '1');
      expect(
        count('count-absent'),
        isWorkDay ? '1' : '0',
      ); // Ben; boss untracked, Gone inactive
      expect(find.textContaining('Present · in 7:55'), findsOneWidget);

      admin.setDay(today, [
        DaySummary(
          userId: 'ana',
          date: today,
          firstIn: DateTime(now.year, now.month, now.day, 7, 55),
          lastIsIn: true,
          tapCount: 1,
        ),
        DaySummary(
          userId: 'ben',
          date: today,
          firstIn: DateTime(now.year, now.month, now.day, 8, 20),
          lastIsIn: true,
          tapCount: 1,
          late: true,
        ),
      ]);
      await tester.pumpAndSettle();
      expect(count('count-late'), '1');
      expect(count('count-absent'), '0');
    });

    testWidgets('can go back a day and not past today', (tester) async {
      await pumpAdminAt(tester, Routes.dashboard);
      final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right),
      );
      expect(next.onPressed, isNull);
      await tester.tap(find.byTooltip('Previous day'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Today'), findsNothing);
    });
  });

  group('employees', () {
    testWidgets('lists active people; search and show deactivated', (
      tester,
    ) async {
      await pumpAdminAt(tester, Routes.employees);
      expect(find.text('Ana Cruz'), findsOneWidget);
      expect(find.text('Gone Away'), findsNothing);
      expect(find.textContaining('Not tracked'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('employee-search')), 'reyes');
      await tester.pumpAndSettle();
      expect(find.text('Ben Reyes'), findsOneWidget);
      expect(find.text('Ana Cruz'), findsNothing);

      await tester.enterText(find.byKey(const Key('employee-search')), '');
      await tester.tap(find.text('Show deactivated'));
      await tester.pumpAndSettle();
      expect(find.text('Gone Away'), findsOneWidget);
    });

    testWidgets('adds an employee', (tester) async {
      await pumpAdminAt(tester, Routes.employeeNew);
      await tester.tap(find.byKey(const Key('form-save')));
      await tester.pumpAndSettle();
      expect(find.text('Required'), findsNWidgets(2));
      expect(admin.created, isEmpty);

      await tester.enterText(find.byKey(const Key('field-name')), 'Carla Diaz');
      await tester.enterText(
        find.byKey(const Key('field-email')),
        'carla@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('field-employee-id')),
        'EMP-010',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'password123',
      );
      await reveal(tester, 'field-track');
      await tester.tap(find.byKey(const Key('field-track')));
      await reveal(tester, 'form-save');
      await tester.tap(find.byKey(const Key('form-save')));
      await tester.pumpAndSettle();

      final d = admin.created.single;
      expect(d.displayName, 'Carla Diaz');
      expect(d.email, 'carla@example.com');
      expect(d.employeeId, 'EMP-010');
      expect(d.role, UserRole.employee);
      expect(d.trackAttendance, isFalse);
      expect(find.text('Added Carla Diaz'), findsOneWidget);
    });

    testWidgets('server errors are shown on the form', (tester) async {
      admin.nextError = const AdminFailure('EMAIL_EXISTS', '');
      await pumpAdminAt(tester, Routes.employeeNew);
      await tester.enterText(find.byKey(const Key('field-name')), 'Ana');
      await tester.enterText(
        find.byKey(const Key('field-email')),
        'ana@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('field-employee-id')),
        'EMP-1',
      );
      await tester.enterText(
        find.byKey(const Key('field-password')),
        'password123',
      );
      await reveal(tester, 'form-save');
      await tester.tap(find.byKey(const Key('form-save')));
      await tester.pumpAndSettle();
      expect(
        find.text('An account with this email already exists.'),
        findsOneWidget,
      );
    });

    testWidgets(
      'edits and deactivates an employee without touching the password',
      (tester) async {
        await pumpAdminAt(tester, Routes.employeeEdit('ana'));
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('field-email')),
                  matching: find.byType(TextField),
                ),
              )
              .enabled,
          isFalse,
        );
        await tester.enterText(
          find.byKey(const Key('field-name')),
          'Ana C. Cruz',
        );
        await reveal(tester, 'field-active');
        await tester.tap(find.byKey(const Key('field-active')));
        await reveal(tester, 'form-save');
        await tester.tap(find.byKey(const Key('form-save')));
        await tester.pumpAndSettle();

        final (uid, d) = admin.updated.single;
        expect(uid, 'ana');
        expect(d.displayName, 'Ana C. Cruz');
        expect(d.active, isFalse);
        expect(d.password, isNull);
      },
    );

    testWidgets(
      'admins cannot deactivate themselves (checked before calling the server)',
      (tester) async {
        await pumpAdminAt(tester, Routes.employeeEdit('boss'));
        await reveal(tester, 'field-active');
        await tester.tap(find.byKey(const Key('field-active')));
        await reveal(tester, 'form-save');
        await tester.tap(find.byKey(const Key('form-save')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('form-error')), findsOneWidget);
        expect(admin.updated, isEmpty);
      },
    );
  });

  testWidgets('employees cannot open admin pages', (tester) async {
    users.put(ana, uid: 'ana');
    final session = SessionController(auth: auth, users: users);
    addTearDown(session.dispose);
    auth
      ..adminClaim = false
      ..emit(const AuthIdentity(uid: 'ana', email: 'ana@example.com'));
    await tester.pumpWidget(
      MgoAttendanceApp(
        services: testServices(auth: auth, session: session, admin: admin),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .go(Routes.employees);
    await tester.pumpAndSettle();
    expect(find.text('Employees'), findsNothing);
    expect(find.byKey(const Key('tap-ready')), findsOneWidget);
  });
}
