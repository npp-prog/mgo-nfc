import '../../models/app_settings.dart';
import '../../models/app_user.dart';
import '../../models/day_summary.dart';

enum DayStatus { present, late, absent }

class DashboardEntry {
  const DashboardEntry(this.user, this.status, this.summary);
  final AppUser user;
  final DayStatus status;

  /// Null when absent.
  final DaySummary? summary;

  /// Still checked in (last tap was a check-in).
  bool get inOffice => summary?.lastIsIn ?? false;
}

class DashboardData {
  const DashboardData({
    required this.date,
    required this.isWorkDay,
    required this.entries,
  });

  final String date;
  final bool isWorkDay;

  /// Sorted: late, absent, present; then by name.
  final List<DashboardEntry> entries;

  Iterable<DashboardEntry> withStatus(DayStatus s) =>
      entries.where((e) => e.status == s);
  int count(DayStatus s) => withStatus(s).length;
  int get inOfficeCount => entries.where((e) => e.inOffice).length;
}

/// Same rules as the payroll export: someone is absent on a work day when they
/// are active, tracked, already hired on [date] and have no taps. Anyone who
/// tapped is listed, even on non-work days or when untracked.
DashboardData buildDashboard({
  required String date,
  required List<AppUser> users,
  required List<DaySummary> summaries,
  required AppSettings settings,
}) {
  final day = DateTime.parse(date);
  final isWorkDay = settings.workDays.contains(day.weekday);
  final byUser = {for (final s in summaries) s.userId: s};
  final entries = <DashboardEntry>[];

  for (final u in users) {
    final s = byUser[u.uid];
    if (s != null && s.tapCount > 0) {
      entries.add(
        DashboardEntry(u, s.late ? DayStatus.late : DayStatus.present, s),
      );
      continue;
    }
    final hired = u.createdAt == null || !_dateOnly(u.createdAt!).isAfter(day);
    if (isWorkDay && u.active && u.trackAttendance && hired) {
      entries.add(DashboardEntry(u, DayStatus.absent, null));
    }
  }

  const order = {DayStatus.late: 0, DayStatus.absent: 1, DayStatus.present: 2};
  entries.sort(
    (a, b) => order[a.status]!.compareTo(order[b.status]!) != 0
        ? order[a.status]!.compareTo(order[b.status]!)
        : a.user.name.toLowerCase().compareTo(b.user.name.toLowerCase()),
  );
  return DashboardData(date: date, isWorkDay: isWorkDay, entries: entries);
}

DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
