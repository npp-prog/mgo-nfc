import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mgo_attendance/src/app.dart';
import 'package:mgo_attendance/src/features/admin/export_screen.dart';
import 'package:mgo_attendance/src/features/admin/settings_screen.dart';
import 'package:mgo_attendance/src/features/admin/tag_write_screen.dart';
import 'package:mgo_attendance/src/models/app_settings.dart';
import 'package:mgo_attendance/src/models/app_user.dart';
import 'package:mgo_attendance/src/models/tag_info.dart';
import 'package:mgo_attendance/src/nfc/ndef_uri.dart';
import 'package:mgo_attendance/src/router.dart';
import 'package:mgo_attendance/src/services/admin_repository.dart';
import 'package:mgo_attendance/src/services/auth_repository.dart';
import 'package:mgo_attendance/src/session/session_controller.dart';
import 'package:nfc_manager/ndef_record.dart';

import 'package:mgo_attendance/src/nfc/simulated_ntag.dart';

import '../fakes/fakes.dart';

const base = 'https://attendance.example.com/tag/';
const uid = '04A1B2C3D4E5F6';

String? urlOn(SimulatedNtag tag) {
  final b = BytesBuilder();
  for (var p = 4; p < tag.type.cfgPage; p++) {
    b.add(tag.page(p));
  }
  final mem = b.toBytes();
  return firstUri(
    NdefMessage.decode(Uint8List.fromList(mem.sublist(2, 2 + mem[1]))),
  );
}

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
  late FakeNfcService nfc;
  late FakeFileSharer files;

  setUp(() {
    auth = FakeAuthRepository()..adminClaim = true;
    users = FakeUserRepository()
      ..put(
        user(uid: 'boss', name: 'Boss', role: UserRole.admin),
        uid: 'boss',
      );
    admin = FakeAdminRepository()
      ..settings.set(const AppSettings(tagUrlBase: base));
    nfc = FakeNfcService();
    files = FakeFileSharer();
  });

  Future<void> pumpAdminAt(WidgetTester tester, String location) async {
    final session = SessionController(auth: auth, users: users);
    addTearDown(session.dispose);
    auth.emit(const AuthIdentity(uid: 'boss', email: 'boss@example.com'));
    await tester.pumpWidget(
      MgoAttendanceApp(
        services: testServices(
          auth: auth,
          session: session,
          admin: admin,
          nfc: nfc,
          files: files,
        ),
      ),
    );
    await tester.pumpAndSettle();
    GoRouter.of(tester.element(find.byType(Scaffold).first)).push(location);
    await tester.pumpAndSettle();
  }

  Future<void> fillNewTag(
    WidgetTester tester, {
    String passphrase = 'office-secret',
  }) async {
    await tester.enterText(find.byKey(const Key('tag-label')), 'Main Entrance');
    await tester.enterText(find.byKey(const Key('tag-location')), 'Lobby');
    await reveal(tester, 'tag-passphrase');
    await tester.enterText(find.byKey(const Key('tag-passphrase')), passphrase);
    await reveal(tester, 'tag-start');
    await tester.tap(find.byKey(const Key('tag-start')));
    await tester.pumpAndSettle();
  }

  group('helpers', () {
    test('slugify', () {
      expect(slugify('Main Entrance'), 'main-entrance');
      expect(slugify('  Back door (parking) '), 'back-door-parking');
      expect(slugify('x' * 80).length, 64);
    });

    test('tag domain <-> URL base', () {
      expect(
        tagUrlBaseFromDomain('Attendance.Example.com'),
        'https://attendance.example.com/tag/',
      );
      expect(
        tagUrlBaseFromDomain('https://att.example.com/whatever'),
        'https://att.example.com/tag/',
      );
      expect(tagUrlBaseFromDomain(' '), '');
      expect(
        domainFromTagUrlBase('https://att.example.com/tag/'),
        'att.example.com',
      );
      expect(domainFromTagUrlBase(''), '');
    });

    test('export presets are semi-monthly payroll periods', () {
      final p = exportPresets(DateTime(2026, 3, 20));
      String r(int i) =>
          '${p[i].$2.start.toIso8601String().substring(0, 10)}..${p[i].$2.end.toIso8601String().substring(0, 10)}';
      expect(r(0), '2026-03-01..2026-03-15');
      expect(r(1), '2026-03-16..2026-03-31');
      expect(r(2), '2026-02-01..2026-02-15');
      expect(r(3), '2026-02-16..2026-02-28');
      expect(r(4), '2026-02-01..2026-02-28');
      // January -> previous December
      expect(
        exportPresets(DateTime(2026, 1, 5))[2].$2.start,
        DateTime(2025, 12, 1),
      );
    });
  });

  group('tag writing', () {
    testWidgets('registers, writes the URL and locks a blank tag', (
      tester,
    ) async {
      await pumpAdminAt(tester, Routes.tagNew);
      expect(
        tester
            .widget<TextField>(
              find.descendant(
                of: find.byKey(const Key('tag-id')),
                matching: find.byType(TextField),
              ),
            )
            .controller!
            .text,
        '',
      );
      await fillNewTag(tester);
      expect(find.byKey(const Key('tag-stage-waiting')), findsOneWidget);
      expect(nfc.writing, isTrue);

      final tag = SimulatedNtag(formatted: false);
      await nfc.present(uid, tag);
      await tester.pumpAndSettle();

      expect(admin.registered.single, {
        'tagId': 'main-entrance',
        'tagUid': uid,
        'label': 'Main Entrance',
        'location': 'Lobby',
        'replace': false,
      });
      expect(urlOn(tag), '${base}main-entrance');
      expect(tag.protected, isTrue);
      expect(find.byKey(const Key('tag-stage-done')), findsOneWidget);
      expect(find.textContaining('NTAG215 · locked'), findsOneWidget);
      expect(nfc.writing, isFalse);
    });

    testWidgets('locking needs a passphrase of 8+ characters', (tester) async {
      await pumpAdminAt(tester, Routes.tagNew);
      await fillNewTag(tester, passphrase: 'short');
      expect(find.text('At least 8 characters to lock'), findsOneWidget);
      expect(nfc.writing, isFalse);
    });

    testWidgets(
      'a failed write keeps the registration and succeeds on the next tap',
      (tester) async {
        await pumpAdminAt(tester, Routes.tagNew);
        await fillNewTag(tester);

        await nfc.present(uid, SimulatedNtag(failAfterWrites: 1));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tag-stage-failed')), findsOneWidget);
        expect(find.textContaining('tap it again to finish'), findsOneWidget);

        final tag = SimulatedNtag();
        await nfc.present(uid, tag);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('tag-stage-done')), findsOneWidget);
        expect(urlOn(tag), '${base}main-entrance');
        expect(admin.registered, hasLength(2));
      },
    );

    testWidgets(
      'server refusal (UID already registered) is shown and nothing is written',
      (tester) async {
        admin.nextError = const AdminFailure(
          'TAG_UID_TAKEN',
          'This physical tag is already registered as "side".',
        );
        await pumpAdminAt(tester, Routes.tagNew);
        await fillNewTag(tester);
        final tag = SimulatedNtag();
        await nfc.present(uid, tag);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('already registered as "side"'),
          findsOneWidget,
        );
        expect(tag.writes, 0);
      },
    );

    testWidgets(
      'replacing a tag asks for confirmation, then registers with replace',
      (tester) async {
        admin
          ..tags.set([
            const TagInfo(
              tagId: 'main',
              uid: '04000000000001',
              label: 'Main',
              location: 'Lobby',
              active: true,
              url: '${base}main',
            ),
          ])
          ..nextError = const AdminFailure('TAG_ID_TAKEN', '');
        await pumpAdminAt(tester, Routes.tagRewrite('main'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<TextField>(
                find.descendant(
                  of: find.byKey(const Key('tag-label')),
                  matching: find.byType(TextField),
                ),
              )
              .controller!
              .text,
          'Main',
        );
        await reveal(tester, 'tag-passphrase');
        await tester.enterText(
          find.byKey(const Key('tag-passphrase')),
          'office-secret',
        );
        await reveal(tester, 'tag-start');
        await tester.tap(find.byKey(const Key('tag-start')));
        await tester.pumpAndSettle();

        final newTag = SimulatedNtag();
        // Present without awaiting: the replace dialog is waiting for the user.
        final presented = nfc.present(uid, newTag);
        await tester.pumpAndSettle();
        expect(find.text('Replace the existing tag?'), findsOneWidget);
        await tester.tap(find.text('Replace'));
        await tester.pumpAndSettle();
        await presented;

        await nfc.present(uid, newTag);
        await tester.pumpAndSettle();
        expect(admin.registered.last['replace'], isTrue);
        expect(admin.registered.last['tagId'], 'main');
        expect(urlOn(newTag), '${base}main');
        expect(find.byKey(const Key('tag-stage-done')), findsOneWidget);
      },
    );

    testWidgets('writing is blocked until the tag domain is set', (
      tester,
    ) async {
      admin.settings.set(const AppSettings());
      await pumpAdminAt(tester, Routes.tagNew);
      expect(find.byKey(const Key('tag-no-base')), findsOneWidget);
      await reveal(tester, 'tag-start');
      expect(
        tester
            .widget<ButtonStyleButton>(find.byKey(const Key('tag-start')))
            .onPressed,
        isNull,
      );
    });
  });

  testWidgets('tags list: disable a tag from the menu', (tester) async {
    admin.tags.set([
      const TagInfo(
        tagId: 'main',
        uid: uid,
        label: 'Main',
        location: 'Lobby',
        active: true,
        url: '${base}main',
      ),
    ]);
    await pumpAdminAt(tester, Routes.tags);
    expect(find.text('Main'), findsOneWidget);
    expect(find.textContaining('UID $uid'), findsOneWidget);
    await tester.tap(find.byKey(const Key('tag-menu-main')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Disable (stops check-ins)'));
    await tester.pumpAndSettle();
    expect(admin.tagUpdates.single, ('main', 'Main', 'Lobby', false));
  });

  testWidgets('export: picks a period and format, then shares the CSV', (
    tester,
  ) async {
    admin.exportResult = const CsvExport(
      filename: 'attendance_raw.csv',
      csv: 'a,b',
      rowCount: 42,
    );
    await pumpAdminAt(tester, Routes.export);
    await tester.tap(find.text('Every tap'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('export-button')));
    await tester.pumpAndSettle();

    final (from, to, raw) = admin.exports.single;
    final now = DateTime.now();
    expect(from, '${now.year}-${now.month.toString().padLeft(2, '0')}-01');
    expect(to.endsWith('-15'), isTrue);
    expect(raw, isTrue);
    expect(files.shared.single, ('attendance_raw.csv', 'a,b', 'text/csv'));
    expect(find.text('attendance_raw.csv: 42 rows'), findsOneWidget);
  });

  testWidgets('export failure is reported', (tester) async {
    admin.nextError = const AdminFailure('NETWORK', '');
    await pumpAdminAt(tester, Routes.export);
    await tester.tap(find.byKey(const Key('export-button')));
    await tester.pumpAndSettle();
    expect(
      find.text('No connection to the server. Try again.'),
      findsOneWidget,
    );
    expect(files.shared, isEmpty);
  });

  group('settings', () {
    testWidgets('saves the tag domain, work days and window', (tester) async {
      admin.settings.set(const AppSettings());
      await pumpAdminAt(tester, Routes.settings);
      await tester.enterText(
        find.byKey(const Key('settings-domain')),
        'attendance.mgocandoniaccounting.org',
      );
      await reveal(tester, 'settings-day-6');
      await tester.tap(find.byKey(const Key('settings-day-6')));
      await reveal(tester, 'settings-save');
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();

      final s = admin.savedSettings.single;
      expect(s.tagUrlBase, 'https://attendance.mgocandoniaccounting.org/tag/');
      expect(s.workDays, [1, 2, 3, 4, 5, 6]);
      expect(s.lateTime, '08:00');
      expect(s.timezone, 'Asia/Manila');
      expect(s.duplicateWindowSeconds, 120);
      expect(find.text('Settings saved'), findsOneWidget);
    });

    testWidgets('rejects a bad domain and time zone', (tester) async {
      await pumpAdminAt(tester, Routes.settings);
      await tester.enterText(
        find.byKey(const Key('settings-domain')),
        'not a domain',
      );
      await tester.enterText(
        find.byKey(const Key('settings-timezone')),
        'Manila time',
      );
      await reveal(tester, 'settings-save');
      await tester.tap(find.byKey(const Key('settings-save')));
      await tester.pumpAndSettle();
      expect(admin.savedSettings, isEmpty);
      await tester.scrollUntilVisible(
        find.text('Enter a domain like attendance.example.com'),
        -150,
        scrollable: find
            .descendant(
              of: find.byType(Form),
              matching: find.byType(Scrollable),
            )
            .first,
      );
      expect(
        find.text('Enter a domain like attendance.example.com'),
        findsOneWidget,
      );
      expect(find.text('Use a name like Asia/Manila'), findsOneWidget);
    });

    testWidgets(
      'changing an existing domain warns that tags must be rewritten',
      (tester) async {
        await pumpAdminAt(tester, Routes.settings);
        expect(find.text('attendance.example.com'), findsOneWidget);
        await tester.enterText(
          find.byKey(const Key('settings-domain')),
          'new.example.com',
        );
        await reveal(tester, 'settings-save');
        await tester.tap(find.byKey(const Key('settings-save')));
        await tester.pumpAndSettle();
        expect(find.text('Change the tag domain?'), findsOneWidget);
        await tester.tap(find.text('Cancel'));
        await tester.pumpAndSettle();
        expect(admin.savedSettings, isEmpty);
      },
    );
  });
}
