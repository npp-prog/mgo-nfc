import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../app_scope.dart';
import '../../models/attendance_record.dart';
import '../../nfc/nfc_service.dart';
import '../../router.dart';
import '../../widgets/sign_out_button.dart';

enum _Phase {
  checking,
  unsupported,
  disabled,
  ready,
  sending,
  success,
  failure,
}

/// Employee home: hold the phone near an entrance tag to check in or out.
///
/// On Android the screen listens continuously while visible. iOS only allows
/// reading from a system sheet, so it shows a "Scan tag" button instead.
class TapScreen extends StatefulWidget {
  const TapScreen({super.key});

  /// Ignore further tags for this long after a tap, so holding the phone on
  /// the tag doesn't send repeats (the server also rejects them).
  static const cooldown = Duration(seconds: 3);

  @override
  State<TapScreen> createState() => _TapScreenState();
}

class _TapScreenState extends State<TapScreen> with WidgetsBindingObserver {
  late final AppServices _services = AppScope.of(context);
  _Phase _phase = _Phase.checking;
  bool _listening = false;
  DateTime _acceptAfter = DateTime.fromMillisecondsSinceEpoch(0);
  TapResult? _result;
  String? _error;

  bool get _isIos => defaultTargetPlatform == TargetPlatform.iOS;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_listening) _services.nfc.stop();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_isIos) return;
    if (state == AppLifecycleState.resumed) {
      _init(); // NFC may have been switched on in settings meanwhile.
    } else if (state == AppLifecycleState.paused && _listening) {
      _listening = false;
      _services.nfc.stop();
    }
  }

  Future<void> _init() async {
    final status = await _services.nfc.status();
    if (!mounted) return;
    switch (status) {
      case NfcStatus.unsupported:
        setState(() => _phase = _Phase.unsupported);
      case NfcStatus.disabled:
        setState(() => _phase = _Phase.disabled);
      case NfcStatus.enabled:
        if (_phase case _Phase.checking || _Phase.disabled) {
          setState(() => _phase = _Phase.ready);
        }
        if (!_isIos) await _listen();
    }
  }

  Future<void> _listen() async {
    if (_listening) return;
    _listening = true;
    try {
      await _services.nfc.start(onTag: _onTag, onError: _onReadError);
    } catch (e) {
      _listening = false;
      _onReadError(e);
    }
  }

  void _onReadError(Object e) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _phase = _Phase.failure;
      _error = e is NfcReadException
          ? e.message
          : 'Could not read the tag. Hold the phone still and try again.';
    });
  }

  Future<void> _onTag(ScannedTag tag) async {
    if (!mounted ||
        _phase == _Phase.sending ||
        DateTime.now().isBefore(_acceptAfter)) {
      return;
    }
    setState(() {
      _phase = _Phase.sending;
      _error = null;
    });
    try {
      final result = await _services.attendance.recordTap(tag);
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.success;
        _result = result;
      });
    } on TapFailure catch (f) {
      HapticFeedback.heavyImpact();
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failure;
        _error = f.message;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _phase = _Phase.failure;
        _error = 'Something went wrong. Please tap again.';
      });
    } finally {
      _acceptAfter = DateTime.now().add(TapScreen.cooldown);
      if (_isIos) _listening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = _services.session;
    final user = session.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: [
          IconButton(
            tooltip: 'My history',
            icon: const Icon(Icons.history),
            onPressed: () => context.push(Routes.history),
          ),
          if (session.isAdmin)
            IconButton(
              tooltip: 'Admin',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.go(Routes.admin),
            ),
          const SignOutButton(),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'Hello, ${user?.name ?? ''}',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            if (user != null && user.employeeId.isNotEmpty)
              Text(user.employeeId),
            const SizedBox(height: 16),
            if (user != null) _TodayCard(uid: user.uid),
            const SizedBox(height: 32),
            _buildStatus(context),
          ],
        ),
      ),
    );
  }

  Widget _buildStatus(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat.jm();
    switch (_phase) {
      case _Phase.checking:
        return const Center(child: CircularProgressIndicator());
      case _Phase.unsupported:
        return const _StatusBlock(
          key: Key('tap-unsupported'),
          icon: Icons.portable_wifi_off,
          title: 'This phone has no NFC',
          message: 'Use a phone with NFC to check in, or ask your admin.',
        );
      case _Phase.disabled:
        return _StatusBlock(
          key: const Key('tap-disabled'),
          icon: Icons.nfc,
          title: 'NFC is turned off',
          message: 'Turn on NFC in your phone settings, then come back to this screen.',
          action: OutlinedButton(
            onPressed: _init,
            child: const Text('Check again'),
          ),
        );
      case _Phase.ready:
        return _StatusBlock(
          key: const Key('tap-ready'),
          icon: Icons.nfc,
          color: scheme.primary,
          title: _isIos ? 'Ready to scan' : 'Hold your phone near the tag',
          message: 'At the office entrance. We work out check-in or check-out for you.',
          action: _scanButton(),
        );
      case _Phase.sending:
        return const _StatusBlock(
          key: Key('tap-sending'),
          icon: Icons.cloud_upload_outlined,
          title: 'Recording…',
          message: 'Keep the app open for a moment.',
          busy: true,
        );
      case _Phase.success:
        final r = _result!;
        final checkIn = r.type == TapType.checkIn;
        return _StatusBlock(
          key: const Key('tap-success'),
          icon: checkIn ? Icons.login : Icons.logout,
          color: r.late ? scheme.tertiary : Colors.green.shade700,
          title:
              '${checkIn ? 'Checked in' : 'Checked out'} at ${time.format(r.timestamp)}',
          message: [
            if (r.late) 'You are late today.',
            if (r.tagLabel.isNotEmpty) r.tagLabel,
          ].join(' · '),
          action: _scanButton(),
        );
      case _Phase.failure:
        return _StatusBlock(
          key: const Key('tap-failure'),
          icon: Icons.error_outline,
          color: scheme.error,
          title: 'Not recorded',
          message: _error ?? '',
          action: _scanButton(),
        );
    }
  }

  Widget? _scanButton() => _isIos
      ? FilledButton.icon(
          onPressed: _listen,
          icon: const Icon(Icons.nfc),
          label: const Text('Scan tag'),
        )
      : null;
}

class _StatusBlock extends StatelessWidget {
  const _StatusBlock({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
    this.color,
    this.action,
    this.busy = false,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color? color;
  final Widget? action;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      liveRegion: true,
      child: Column(
        children: [
          busy
              ? const SizedBox.square(
                  dimension: 96,
                  child: CircularProgressIndicator(strokeWidth: 6),
                )
              : Icon(icon, size: 96, color: color),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.titleLarge?.copyWith(color: color),
          ),
          if (message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
          ],
          if (action != null) ...[const SizedBox(height: 24), action!],
        ],
      ),
    );
  }
}

/// Today's first check-in / last check-out, live from Firestore.
class _TodayCard extends StatelessWidget {
  const _TodayCard({required this.uid});
  final String uid;

  @override
  Widget build(BuildContext context) {
    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final time = DateFormat.jm();
    return StreamBuilder<List<AttendanceRecord>>(
      stream: AppScope.of(context).attendance.watchMyRecords(uid, limit: 20),
      builder: (context, snap) {
        final day = AttendanceDay(
          today,
          (snap.data ?? const []).where((r) => r.date == today).toList(),
        );
        final String text;
        if (!snap.hasData) {
          text = 'Loading today…';
        } else if (day.taps.isEmpty) {
          text = 'Not checked in yet today';
        } else {
          final inText =
              'In ${time.format(day.firstIn!.timestamp)}${day.late ? ' (late)' : ''}';
          text = day.missingCheckOut
              ? '$inText · currently checked in'
              : '$inText · Out ${time.format(day.lastOut!.timestamp)}';
        }
        return Card(
          child: ListTile(
            key: const Key('today-card'),
            leading: const Icon(Icons.today),
            title: const Text('Today'),
            subtitle: Text(text),
          ),
        );
      },
    );
  }
}
