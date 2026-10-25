import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/app_settings.dart';

/// "https://att.example.com/tag/" <-> "att.example.com"
String domainFromTagUrlBase(String base) {
  final m = RegExp(r'^https://([^/]+)/tag/$').firstMatch(base);
  return m?.group(1) ?? '';
}

String tagUrlBaseFromDomain(String domain) {
  final d = domain
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'^https?://'), '')
      .replaceAll(RegExp(r'/.*$'), '');
  return d.isEmpty ? '' : 'https://$d/tag/';
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Settings')),
    body: StreamBuilder<AppSettings>(
      stream: AppScope.of(context).admin.watchSettings(),
      builder: (context, snap) {
        if (snap.hasError) {
          return const Center(child: Text('Could not load settings.'));
        }
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _SettingsForm(initial: snap.data!);
      },
    ),
  );
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.initial});
  final AppSettings initial;

  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final _formKey = GlobalKey<FormState>();
  late final _domain = TextEditingController(
    text: domainFromTagUrlBase(widget.initial.tagUrlBase),
  );
  late final _timezone = TextEditingController(text: widget.initial.timezone);
  late String _lateTime = widget.initial.lateTime;
  late int _windowSeconds = widget.initial.duplicateWindowSeconds;
  late final Set<int> _workDays = {...widget.initial.workDays};
  bool _busy = false;

  @override
  void dispose() {
    _domain.dispose();
    _timezone.dispose();
    super.dispose();
  }

  Future<void> _pickLateTime() async {
    final parts = _lateTime.split(':').map(int.parse).toList();
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: parts[0], minute: parts[1]),
    );
    if (t != null) {
      setState(
        () => _lateTime =
            '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}',
      );
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final services = AppScope.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final newBase = tagUrlBaseFromDomain(_domain.text);
    final oldBase = widget.initial.tagUrlBase;
    if (oldBase.isNotEmpty && newBase != oldBase) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Change the tag domain?'),
          content: const Text(
            'Tags already written still carry the old URL and will stop working until '
            'they are rewritten. The Android app also needs tagHost updated and a new build.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Change'),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }
    setState(() => _busy = true);
    try {
      await services.admin.saveSettings(
        AppSettings(
          lateTime: _lateTime,
          timezone: _timezone.text.trim(),
          duplicateWindowSeconds: _windowSeconds,
          tagUrlBase: newBase,
          workDays: _workDays.toList()..sort(),
        ),
      );
      messenger.showSnackBar(const SnackBar(content: Text('Settings saved')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Could not save settings. Check the values and your connection.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    final windows = {60, 120, 300, 600, _windowSeconds}.toList()..sort();
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextFormField(
            key: const Key('settings-domain'),
            controller: _domain,
            decoration: InputDecoration(
              labelText: 'Tag domain',
              hintText: 'attendance.mgocandoniaccounting.org',
              border: const OutlineInputBorder(),
              helperText: _domain.text.trim().isEmpty
                  ? 'Needed before writing tags'
                  : 'Tags get ${tagUrlBaseFromDomain(_domain.text)}<tag-id>',
            ),
            keyboardType: TextInputType.url,
            onChanged: (_) => setState(() {}),
            validator: (v) {
              final d = (v ?? '').trim();
              if (d.isEmpty) return null;
              return RegExp(
                    r'^(https?://)?[a-z0-9-]+(\.[a-z0-9-]+)+/?$',
                    caseSensitive: false,
                  ).hasMatch(d)
                  ? null
                  : 'Enter a domain like attendance.example.com';
            },
          ),
          gap,
          ListTile(
            key: const Key('settings-late'),
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Late after'),
            subtitle: Text(
              '$_lateTime (first check-in after this minute is late)',
            ),
            trailing: const Icon(Icons.edit),
            onTap: _pickLateTime,
          ),
          gap,
          TextFormField(
            key: const Key('settings-timezone'),
            controller: _timezone,
            decoration: const InputDecoration(
              labelText: 'Office time zone',
              helperText: 'IANA name, e.g. Asia/Manila',
              border: OutlineInputBorder(),
            ),
            validator: (v) =>
                RegExp(r'^[A-Za-z_]+(/[A-Za-z0-9_+\-]+)+$|^UTC$')
                    .hasMatch((v ?? '').trim())
                ? null
                : 'Use a name like Asia/Manila',
          ),
          gap,
          DropdownButtonFormField<int>(
            key: const Key('settings-window'),
            initialValue: _windowSeconds,
            decoration: const InputDecoration(
              labelText: 'Ignore repeat taps within',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final s in windows)
                DropdownMenuItem(
                  value: s,
                  child: Text(s % 60 == 0 ? '${s ~/ 60} min' : '$s s'),
                ),
            ],
            onChanged: (v) => setState(() => _windowSeconds = v!),
          ),
          gap,
          Text('Work days', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            children: [
              for (var d = 1; d <= 7; d++)
                FilterChip(
                  key: Key('settings-day-$d'),
                  label: Text(_weekdays[d - 1]),
                  selected: _workDays.contains(d),
                  onSelected: (on) => setState(
                    () => on ? _workDays.add(d) : _workDays.remove(d),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton(
            key: const Key('settings-save'),
            onPressed: _busy ? null : _save,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Save'),
            ),
          ),
        ],
      ),
    );
  }
}
