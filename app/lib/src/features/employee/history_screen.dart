import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../models/attendance_record.dart';

/// The signed-in user's own attendance, grouped by day.
class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    final uid = services.session.user?.uid;
    return Scaffold(
      appBar: AppBar(title: const Text('My history')),
      body: uid == null
          ? const SizedBox.shrink()
          : StreamBuilder<List<AttendanceRecord>>(
              stream: services.attendance.watchMyRecords(uid),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const Center(
                    child: Text('Could not load your history.'),
                  );
                }
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final days = AttendanceDay.group(snap.data!);
                if (days.isEmpty) {
                  return const Center(
                    child: Text('No attendance recorded yet.'),
                  );
                }
                return ListView.separated(
                  itemCount: days.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _DayTile(day: days[i]),
                );
              },
            ),
    );
  }
}

class _DayTile extends StatelessWidget {
  const _DayTile({required this.day});
  final AttendanceDay day;

  static String formatDuration(Duration d) {
    final h = d.inHours, m = d.inMinutes % 60;
    return h == 0 ? '${m}m' : '${h}h ${m.toString().padLeft(2, '0')}m';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat.jm();
    final date = DateFormat('EEE, d MMM y').format(DateTime.parse(day.date));
    final inText = day.firstIn == null
        ? '—'
        : time.format(day.firstIn!.timestamp);
    final outText = day.missingCheckOut
        ? 'no check-out'
        : (day.lastOut == null ? '—' : time.format(day.lastOut!.timestamp));
    return ExpansionTile(
      key: Key('day-${day.date}'),
      title: Row(
        children: [
          Expanded(child: Text(date)),
          if (day.late)
            Chip(
              label: const Text('Late'),
              visualDensity: VisualDensity.compact,
              backgroundColor: scheme.tertiaryContainer,
            ),
        ],
      ),
      subtitle: Text(
        'In $inText · Out $outText · ${formatDuration(day.worked)}',
      ),
      children: [
        for (final t in day.taps)
          ListTile(
            dense: true,
            leading: Icon(
              t.type == TapType.checkIn ? Icons.login : Icons.logout,
            ),
            title: Text(
              '${t.type == TapType.checkIn ? 'Check-in' : 'Check-out'} · ${time.format(t.timestamp)}',
            ),
            subtitle: Text(t.tagId),
          ),
      ],
    );
  }
}
