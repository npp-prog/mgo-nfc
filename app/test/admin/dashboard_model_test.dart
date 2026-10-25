import 'package:flutter_test/flutter_test.dart';
import 'package:mgo_attendance/src/features/admin/dashboard_model.dart';
import 'package:mgo_attendance/src/models/app_settings.dart';
import 'package:mgo_attendance/src/models/app_user.dart';
import 'package:mgo_attendance/src/models/day_summary.dart';

import '../fakes/fakes.dart';

const monday = '2026-10-26';
const saturday = '2026-10-31';

DaySummary day(
  String uid, {
  bool late = false,
  bool stillIn = true,
  String date = monday,
}) => DaySummary(
  userId: uid,
  date: date,
  firstIn: DateTime(2026, 10, 26, late ? 8 : 7, 50),
  lastOut: stillIn ? null : DateTime(2026, 10, 26, 17),
  lastIsIn: stillIn,
  tapCount: stillIn ? 1 : 2,
  late: late,
);

void main() {
  final users = [
    user(uid: 'ana', name: 'Ana'),
    user(uid: 'ben', name: 'Ben'),
    user(uid: 'cy', name: 'Cy'),
    user(
      uid: 'boss',
      name: 'Boss',
      role: UserRole.admin,
      trackAttendance: false,
    ),
    user(uid: 'gone', name: 'Gone', active: false),
    user(uid: 'new', name: 'Newbie', createdAt: DateTime(2026, 10, 27, 9)),
  ];

  test('classifies present, late and absent on a work day', () {
    final d = buildDashboard(
      date: monday,
      users: users,
      summaries: [day('ana'), day('ben', late: true, stillIn: false)],
      settings: const AppSettings(),
    );
    expect(d.isWorkDay, isTrue);
    expect(d.withStatus(DayStatus.present).map((e) => e.user.uid), ['ana']);
    expect(d.withStatus(DayStatus.late).map((e) => e.user.uid), ['ben']);
    // untracked admin, deactivated and not-yet-hired people are never absent
    expect(d.withStatus(DayStatus.absent).map((e) => e.user.uid), ['cy']);
    expect(d.inOfficeCount, 1);
    // order: late, absent, present
    expect(d.entries.map((e) => e.user.uid), ['ben', 'cy', 'ana']);
  });

  test('untracked or deactivated people who tapped are still listed', () {
    final d = buildDashboard(
      date: monday,
      users: users,
      summaries: [day('boss'), day('gone')],
      settings: const AppSettings(),
    );
    expect(
      d.withStatus(DayStatus.present).map((e) => e.user.uid),
      containsAll(['boss', 'gone']),
    );
  });

  test('new hire counts from their start date', () {
    final d = buildDashboard(
      date: '2026-10-27',
      users: users,
      summaries: [],
      settings: const AppSettings(),
    );
    expect(
      d.withStatus(DayStatus.absent).map((e) => e.user.uid),
      containsAll(['ana', 'new']),
    );
  });

  test('nobody is absent on a non-work day, but weekend work shows', () {
    final d = buildDashboard(
      date: saturday,
      users: users,
      summaries: [day('ana', date: saturday)],
      settings: const AppSettings(),
    );
    expect(d.isWorkDay, isFalse);
    expect(d.count(DayStatus.absent), 0);
    expect(d.count(DayStatus.present), 1);
  });

  test('work days come from settings', () {
    final d = buildDashboard(
      date: saturday,
      users: users,
      summaries: [],
      settings: const AppSettings(workDays: [1, 2, 3, 4, 5, 6]),
    );
    expect(d.isWorkDay, isTrue);
    expect(d.count(DayStatus.absent), 4);
  });
}
