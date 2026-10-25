import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../models/app_settings.dart';
import '../../models/app_user.dart';
import '../../models/day_summary.dart';
import 'dashboard_model.dart';

/// Present / late / absent for one day, live.
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key, this.initialDate});

  /// For tests; defaults to today.
  final DateTime? initialDate;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late DateTime _date = _dateOnly(widget.initialDate ?? DateTime.now());
  final _isoDate = DateFormat('yyyy-MM-dd');

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  bool get _isToday => _date == _dateOnly(DateTime.now());

  void _shift(int days) =>
      setState(() => _date = _date.add(Duration(days: days)));

  Future<void> _pick() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2024),
      lastDate: _dateOnly(DateTime.now()),
    );
    if (picked != null) setState(() => _date = picked);
  }

  @override
  Widget build(BuildContext context) {
    final admin = AppScope.of(context).admin;
    final date = _isoDate.format(_date);
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance today')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                IconButton(
                  tooltip: 'Previous day',
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _shift(-1),
                ),
                Expanded(
                  child: TextButton(
                    key: const Key('dashboard-date'),
                    onPressed: _pick,
                    child: Text(
                      _isToday
                          ? 'Today, ${DateFormat('EEE d MMM').format(_date)}'
                          : DateFormat('EEE, d MMM y').format(_date),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Next day',
                  icon: const Icon(Icons.chevron_right),
                  onPressed: _isToday ? null : () => _shift(1),
                ),
              ],
            ),
          ),
          Expanded(
            child: StreamBuilder<AppSettings>(
              stream: admin.watchSettings(),
              builder: (context, settingsSnap) => StreamBuilder<List<AppUser>>(
                stream: admin.watchUsers(),
                builder: (context, usersSnap) =>
                    StreamBuilder<List<DaySummary>>(
                      key: ValueKey(date),
                      stream: admin.watchDaySummaries(date),
                      builder: (context, daySnap) {
                        if (usersSnap.hasError || daySnap.hasError) {
                          return const Center(
                            child: Text('Could not load attendance.'),
                          );
                        }
                        if (!usersSnap.hasData || !daySnap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final data = buildDashboard(
                          date: date,
                          users: usersSnap.data!,
                          summaries: daySnap.data!,
                          settings: settingsSnap.data ?? const AppSettings(),
                        );
                        return _DashboardBody(data: data);
                      },
                    ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});
  final DashboardData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat.jm();
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Count(
                'Present',
                data.count(DayStatus.present),
                Colors.green.shade700,
                key: const Key('count-present'),
              ),
              _Count(
                'Late',
                data.count(DayStatus.late),
                scheme.tertiary,
                key: const Key('count-late'),
              ),
              _Count(
                'Absent',
                data.count(DayStatus.absent),
                scheme.error,
                key: const Key('count-absent'),
              ),
              _Count(
                'In office now',
                data.inOfficeCount,
                scheme.primary,
                key: const Key('count-in'),
              ),
            ],
          ),
        ),
        if (!data.isWorkDay)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text('Not a work day: nobody is counted absent.'),
          ),
        const SizedBox(height: 8),
        if (data.entries.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('No one to show for this day.')),
          ),
        for (final e in data.entries)
          ListTile(
            key: Key('entry-${e.user.uid}'),
            leading: CircleAvatar(
              backgroundColor: switch (e.status) {
                DayStatus.present => Colors.green.shade100,
                DayStatus.late => scheme.tertiaryContainer,
                DayStatus.absent => scheme.errorContainer,
              },
              child: Icon(switch (e.status) {
                DayStatus.present => Icons.check,
                DayStatus.late => Icons.schedule,
                DayStatus.absent => Icons.close,
              }, size: 20),
            ),
            title: Text(e.user.name),
            subtitle: Text(switch (e.status) {
              DayStatus.absent => 'Absent',
              _ => [
                '${e.status == DayStatus.late ? 'Late' : 'Present'} · in ${time.format(e.summary!.firstIn!)}',
                if (e.inOffice)
                  'in office'
                else if (e.summary!.lastOut != null)
                  'out ${time.format(e.summary!.lastOut!)}',
              ].join(' · '),
            }),
            trailing: Text(e.user.employeeId),
          ),
      ],
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.label, this.value, this.color, {super.key});
  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(context).textTheme.headlineMedium
                ?.copyWith(color: color),
          ),
          Text(label),
        ],
      ),
    ),
  );
}
