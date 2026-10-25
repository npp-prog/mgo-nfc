import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mgo_attendance/src/app.dart';
import 'package:mgo_attendance/src/models/app_settings.dart';
import 'package:mgo_attendance/src/models/app_user.dart';
import 'package:mgo_attendance/src/models/attendance_record.dart';
import 'package:mgo_attendance/src/models/tag_info.dart';
import 'package:mgo_attendance/src/nfc/nfc_service.dart';
import 'package:mgo_attendance/src/router.dart';
import 'package:mgo_attendance/src/services/auth_repository.dart';
import 'package:mgo_attendance/src/session/session_controller.dart';

import '../fakes/fakes.dart';

const base = 'https://attendance.example.com/tag/';
const mainTag = TagInfo(
  tagId: 'main-entrance',
  uid: '04A1B2C3D4E5F6',
  label: 'Main entrance',
  location: 'Lobby',
  active: true,
  url: '${base}main-entrance',
);

void main() {
  late FakeAuthRepository auth;
  late FakeUserRepository users;
  late FakeAdminRepository admin;
  late FakeAttendanceRepository attendance;
  late FakeNfcService nfc;

  setUp(() {
    auth = FakeAuthRepository();
    users = FakeUserRepository()
      ..put(user(), uid: 'u1')
      ..put(
        user(uid: 'boss', name: 'Boss', role: UserRole.admin),
        uid: 'boss',
      );
    admin = FakeAdminRepository()
      ..tags.set([mainTag])
      ..settings.set(const AppSettings(tagUrlBase: base));
    attendance = FakeAttendanceRepository();
    nfc = FakeNfcService()..current = NfcStatus.unsupported; // e.g. Chrome
  });

  Future<void> pump(
    WidgetTester tester, {
    required String uid,
    bool simulate = true,
  }) async {
    final session = SessionController(auth: auth, users: users);
    addTearDown(session.dispose);
    auth
      ..adminClaim = uid == 'boss'
      ..emit(AuthIdentity(uid: uid, email: '$uid@example.com'));
    await tester.pumpWidget(
      MgoAttendanceApp(
        services: testServices(
          auth: auth,
          session: session,
          nfc: nfc,
          attendance: attendance,
          admin: admin,
          simulateNfc: simulate,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('no simulate button outside test mode', (tester) async {
    await pump(tester, uid: 'u1', simulate: false);
    expect(find.byKey(const Key('tap-unsupported')), findsOneWidget);
    expect(find.byKey(const Key('simulate-tap')), findsNothing);
    expect(find.textContaining('Test mode'), findsNothing);
  });

  testWidgets('simulated tap sends the chosen tag', (tester) async {
    attendance.responses.add(
      TapResult(
        type: TapType.checkIn,
        timestamp: DateTime(2026, 10, 26, 7, 55),
        late: false,
        tagLabel: 'Main entrance',
      ),
    );
    await pump(tester, uid: 'u1');
    expect(find.textContaining('Simulate tag tap'), findsWidgets);
    await tester.tap(find.byKey(const Key('simulate-tap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sim-tag-main-entrance')));
    await tester.pumpAndSettle();

    expect(attendance.sent.single.uid, mainTag.uid);
    expect(attendance.sent.single.url, mainTag.url);
    expect(find.byKey(const Key('tap-success')), findsOneWidget);
  });

  testWidgets('simulated cloned and foreign tags send a wrong UID / no URL', (
    tester,
  ) async {
    attendance.responses
      ..add(const TapFailure('TAG_UID_MISMATCH'))
      ..add(const TapFailure('INVALID_TAG_URL'));
    await pump(tester, uid: 'u1');

    await tester.tap(find.byKey(const Key('simulate-tap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sim-cloned')));
    await tester.pumpAndSettle();
    expect(attendance.sent.last.uid, isNot(mainTag.uid));
    expect(attendance.sent.last.url, mainTag.url);
    expect(find.textContaining('could not be verified'), findsOneWidget);

    await tester.tap(find.byKey(const Key('simulate-tap')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('sim-foreign')));
    await tester.pumpAndSettle();
    expect(attendance.sent.last.url, isNull);
    expect(find.text('This is not an office attendance tag.'), findsOneWidget);
  });

  testWidgets('admin writes a tag with a simulated blank sticker', (
    tester,
  ) async {
    await pump(tester, uid: 'boss');
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .push(Routes.tagNew);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-label')), 'Test door');
    await tester.enterText(
      find.byKey(const Key('tag-passphrase')),
      'office-secret',
    );
    await tester.ensureVisible(find.byKey(const Key('tag-start')));
    await tester.tap(find.byKey(const Key('tag-start')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('tag-stage-waiting')), findsOneWidget);
    expect(nfc.writing, isFalse, reason: 'no NFC session without hardware');
    await tester.tap(find.byKey(const Key('tag-simulate')));
    await tester.pumpAndSettle();

    expect(admin.registered.single['tagId'], 'test-door');
    expect((admin.registered.single['tagUid'] as String).length, 14);
    expect(find.byKey(const Key('tag-stage-done')), findsOneWidget);
    expect(find.textContaining('locked · simulated'), findsOneWidget);
  });

  testWidgets('without test mode, a phone without NFC cannot write tags', (
    tester,
  ) async {
    await pump(tester, uid: 'boss', simulate: false);
    GoRouter.of(tester.element(find.byType(Scaffold).first))
        .push(Routes.tagNew);
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('tag-label')), 'Test door');
    await tester.enterText(
      find.byKey(const Key('tag-passphrase')),
      'office-secret',
    );
    await tester.ensureVisible(find.byKey(const Key('tag-start')));
    await tester.tap(find.byKey(const Key('tag-start')));
    await tester.pumpAndSettle();
    expect(find.text('This phone has no NFC.'), findsOneWidget);
    expect(find.byKey(const Key('tag-simulate')), findsNothing);
  });
}
