import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../services/admin_repository.dart';

/// Payroll periods offered as one-tap presets.
@visibleForTesting
List<(String, DateTimeRange)> exportPresets(DateTime today) {
  final t = DateTime(today.year, today.month, today.day);
  final firstThis = DateTime(t.year, t.month, 1);
  final lastThis = DateTime(t.year, t.month + 1, 0);
  final firstPrev = DateTime(t.year, t.month - 1, 1);
  final lastPrev = DateTime(t.year, t.month, 0);
  final month = DateFormat('MMM');
  return [
    (
      '${month.format(t)} 1–15',
      DateTimeRange(start: firstThis, end: DateTime(t.year, t.month, 15)),
    ),
    (
      '${month.format(t)} 16–${lastThis.day}',
      DateTimeRange(start: DateTime(t.year, t.month, 16), end: lastThis),
    ),
    (
      '${month.format(firstPrev)} 1–15',
      DateTimeRange(
        start: firstPrev,
        end: DateTime(firstPrev.year, firstPrev.month, 15),
      ),
    ),
    (
      '${month.format(firstPrev)} 16–${lastPrev.day}',
      DateTimeRange(
        start: DateTime(firstPrev.year, firstPrev.month, 16),
        end: lastPrev,
      ),
    ),
    (
      'All of ${month.format(firstPrev)}',
      DateTimeRange(start: firstPrev, end: lastPrev),
    ),
  ];
}

class ExportScreen extends StatefulWidget {
  const ExportScreen({super.key, this.today});

  /// For tests; defaults to now.
  final DateTime? today;

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  late final _presets = exportPresets(widget.today ?? DateTime.now());
  late DateTimeRange _range = _presets.first.$2;
  bool _raw = false;
  bool _busy = false;
  final _iso = DateFormat('yyyy-MM-dd');
  final _pretty = DateFormat('d MMM y');

  Future<void> _pickCustom() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 31)),
      initialDateRange: _range,
    );
    if (picked != null) setState(() => _range = picked);
  }

  Future<void> _export() async {
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final res = await services.admin.exportCsv(
        from: _iso.format(_range.start),
        to: _iso.format(_range.end),
        raw: _raw,
      );
      await services.files.shareText(
        filename: res.filename,
        content: res.csv,
        mimeType: 'text/csv',
      );
      messenger.showSnackBar(
        SnackBar(content: Text('${res.filename}: ${res.rowCount} rows')),
      );
    } on AdminFailure catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Export failed. Check your connection and try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Export to CSV')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('Period', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final (label, range) in _presets)
                ChoiceChip(
                  label: Text(label),
                  selected: _range == range,
                  onSelected: (_) => setState(() => _range = range),
                ),
              ActionChip(
                avatar: const Icon(Icons.date_range, size: 18),
                label: const Text('Custom…'),
                onPressed: _pickCustom,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${_pretty.format(_range.start)} – ${_pretty.format(_range.end)}',
            key: const Key('export-range'),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
          const SizedBox(height: 24),
          Text('Format', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: false, label: Text('Daily (payroll)')),
              ButtonSegment(value: true, label: Text('Every tap')),
            ],
            selected: {_raw},
            onSelectionChanged: (s) => setState(() => _raw = s.first),
          ),
          const SizedBox(height: 8),
          Text(
            _raw ? 'One row per tap with time, type, tag and late flag.' : 'One row per employee per day: Present/Late/Absent, first in, last out, hours worked.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            key: const Key('export-button'),
            onPressed: _busy ? null : _export,
            icon: _busy
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Export and share'),
            ),
          ),
        ],
      ),
    );
  }
}
