import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';
import 'package:mgo_attendance/src/app.dart';
import 'package:mgo_attendance/src/models/attendance_record.dart';
import 'package:mgo_attendance/src/nfc/nfc_service.dart';
import 'package:mgo_attendance/src/services/auth_repository.dart';
import 'package:mgo_attendance/src/session/session_controller.dart';

import '../fakes/fakes.dart';

const tag = ScannedTag(
  uid: '04A1B2C3D4E5F6',
  url: 'https://attendance.example.com/tag/main-entrance',
);

void main() {
  late FakeAuthRepository auth;
  late FakeUserRepository users;
  late FakeNfcService nfc;
  late FakeAttendanceRepository attendance;

  setUp(() {
    auth = FakeAuthRepository();
    users = FakeUserRepository()..put(user(), uid: 'u1');
    nfc = FakeNfcService();
    attendance = FakeAttendanceRepository();
  });

  /// Starts the app signed in as an employee, on the tap screen.
  Future<void> pumpSignedIn(WidgetTester tester) async {
    final session = SessionController(auth: auth, users: users);
    addTearDown(session.dispose);
    auth.emit(const AuthIdentity(uid: 'u1', email: 'u1@example.com'));
    await tester.pumpWidget(
      MgoAttendanceApp(
        services: testServices(
          auth: auth,
          session: session,
          nfc: nfc,
          attendance: attendance,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  TapResult result(
    TapType type, {
    bool late = false,
    int hour = 7,
    int minute = 55,
  }) => TapResult(
    type: type,
    timestamp: DateTime(2026, 10, 26, hour, minute),
    late: late,
    tagLabel: 'Main entrance',
  );

  testWidgets('starts listening and shows the ready state', (tester) async {
    await pumpSignedIn(tester);
    expect(find.byKey(const Key('tap-ready')), findsOneWidget);
    expect(nfc.listening, isTrue);
    expect(find.text('Hello, Juan dela Cruz'), findsOneWidget);
  });

  testWidgets('a tap sends UID + URL and shows the check-in', (tester) async {
    attendance.responses.add(result(TapType.checkIn));
    await pumpSignedIn(tester);

    nfc.tap(tag);
    await tester.pumpAndSettle();

    expect(attendance.sent.single.uid, '04A1B2C3D4E5F6');
    expect(attendance.sent.single.url, tag.url);
    expect(find.byKey(const Key('tap-success')), findsOneWidget);
    expect(find.text('Checked in at 7:55 AM'), findsOneWidget);
    expect(find.textContaining('Main entrance'), findsOneWidget);
  });

  testWidgets('shows a sending state while the server responds', (
    tester,
  ) async {
    attendance
      ..gate = Completer<void>()
      ..responses.add(result(TapType.checkOut, hour: 17, minute: 20));
    await pumpSignedIn(tester);

    nfc.tap(tag);
    await tester.pump();
    expect(find.byKey(const Key('tap-sending')), findsOneWidget);

    attendance.gate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('Checked out at 5:20 PM'), findsOneWidget);
  });

  testWidgets('late check-in is called out', (tester) async {
    attendance.responses.add(
      result(TapType.checkIn, late: true, hour: 8, minute: 15),
    );
    await pumpSignedIn(tester);
    nfc.tap(tag);
    await tester.pumpAndSettle();
    expect(find.textContaining('You are late today.'), findsOneWidget);
  });

  testWidgets('server rejection shows the friendly reason', (tester) async {
    attendance.responses.add(
      const TapFailure(
        'DUPLICATE_TAP',
        retryAfterSeconds: 90,
        lastType: TapType.checkIn,
      ),
    );
    await pumpSignedIn(tester);
    nfc.tap(tag);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tap-failure')), findsOneWidget);
    expect(
      find.text(
        'Already recorded your check-in. Wait 1 min 30 s before tapping again.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('cloned/unknown tag message', (tester) async {
    attendance.responses.add(const TapFailure('TAG_UID_MISMATCH'));
    await pumpSignedIn(tester);
    nfc.tap(tag);
    await tester.pumpAndSettle();
    expect(find.textContaining('could not be verified'), findsOneWidget);
  });

  testWidgets('tags held on the phone are not sent twice within the cooldown', (
    tester,
  ) async {
    attendance.responses.add(result(TapType.checkIn));
    await pumpSignedIn(tester);
    nfc.tap(tag);
    await tester.pumpAndSettle();
    nfc.tap(tag);
    nfc.tap(tag);
    await tester.pumpAndSettle();
    expect(attendance.sent, hasLength(1));
  });

  testWidgets('a second tag while sending is ignored', (tester) async {
    attendance
      ..gate = Completer<void>()
      ..responses.add(result(TapType.checkIn));
    await pumpSignedIn(tester);
    nfc.tap(tag);
    await tester.pump();
    nfc.tap(tag);
    attendance.gate!.complete();
    await tester.pumpAndSettle();
    expect(attendance.sent, hasLength(1));
  });

  testWidgets('tag read errors are shown', (tester) async {
    await pumpSignedIn(tester);
    nfc.readError(const NfcReadException('Could not read the tag ID.'));
    await tester.pumpAndSettle();
    expect(find.text('Could not read the tag ID.'), findsOneWidget);
  });

  testWidgets('NFC off: explains, then recovers after "Check again"', (
    tester,
  ) async {
    nfc.current = NfcStatus.disabled;
    await pumpSignedIn(tester);
    expect(find.byKey(const Key('tap-disabled')), findsOneWidget);
    expect(nfc.listening, isFalse);

    nfc.current = NfcStatus.enabled;
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('tap-ready')), findsOneWidget);
    expect(nfc.listening, isTrue);
  });

  testWidgets('phone without NFC', (tester) async {
    nfc.current = NfcStatus.unsupported;
    await pumpSignedIn(tester);
    expect(find.byKey(const Key('tap-unsupported')), findsOneWidget);
  });

  testWidgets(
    'stops NFC when the app goes to the background and restarts on resume',
    (tester) async {
      await pumpSignedIn(tester);
      expect(nfc.starts, 1);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(nfc.listening, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(nfc.listening, isTrue);
      expect(nfc.starts, 2);
    },
  );

  testWidgets("today card reflects today's taps", (tester) async {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    await pumpSignedIn(tester);
    expect(find.text('Not checked in yet today'), findsOneWidget);

    attendance.setRecords([rec(today, 8, 5, TapType.checkIn, late: true)]);
    await tester.pumpAndSettle();
    expect(
      find.text('In 8:05 AM (late) · currently checked in'),
      findsOneWidget,
    );

    attendance.setRecords([
      rec(today, 17, 30, TapType.checkOut),
      rec(today, 8, 5, TapType.checkIn, late: true),
    ]);
    await tester.pumpAndSettle();
    expect(find.text('In 8:05 AM (late) · Out 5:30 PM'), findsOneWidget);
  });

  testWidgets('history groups taps by day with hours and late badge', (
    tester,
  ) async {
    attendance.setRecords([
      rec('2026-10-27', 8, 15, TapType.checkIn, late: true),
      rec('2026-10-26', 17, 20, TapType.checkOut),
      rec('2026-10-26', 13, 0, TapType.checkIn),
      rec('2026-10-26', 12, 0, TapType.checkOut),
      rec('2026-10-26', 7, 50, TapType.checkIn),
    ]);
    await pumpSignedIn(tester);
    await tester.tap(find.byTooltip('My history'));
    await tester.pumpAndSettle();

    expect(find.text('Tue, 27 Oct 2026'), findsOneWidget);
    expect(find.text('In 8:15 AM · Out no check-out · 0m'), findsOneWidget);
    expect(find.text('Mon, 26 Oct 2026'), findsOneWidget);
    expect(find.text('In 7:50 AM · Out 5:20 PM · 8h 30m'), findsOneWidget);
    expect(find.text('Late'), findsOneWidget);

    await tester.tap(find.text('Mon, 26 Oct 2026'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Check-in ·'), findsNWidgets(2));
    expect(find.textContaining('Check-out ·'), findsNWidgets(2));
  });

  testWidgets('history empty state', (tester) async {
    await pumpSignedIn(tester);
    await tester.tap(find.byTooltip('My history'));
    await tester.pumpAndSettle();
    expect(find.text('No attendance recorded yet.'), findsOneWidget);
  });
}
