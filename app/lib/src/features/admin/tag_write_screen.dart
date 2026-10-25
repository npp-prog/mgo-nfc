import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/app_settings.dart';
import '../../models/tag_info.dart';
import '../../nfc/nfc_service.dart';
import '../../nfc/ntag_programmer.dart';
import '../../nfc/simulated_ntag.dart';
import '../../router.dart';
import '../../services/admin_repository.dart';

/// Turns a label into a tag ID: "Main Entrance" -> "main-entrance".
String slugify(String s) {
  final slug = s
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.length > 64 ? slug.substring(0, 64) : slug;
}

enum _Stage { form, waiting, registering, writing, done, failed }

/// Add a new tag ([tagId] == null) or rewrite/replace an existing one.
///
/// Order: read UID -> registerTag (server validates and returns the URL) ->
/// write URL with raw NTAG commands -> optionally lock. Registration is
/// idempotent, so a failed write is fixed by simply tapping again.
class TagWriteScreen extends StatefulWidget {
  const TagWriteScreen({super.key, this.tagId});
  final String? tagId;

  @override
  State<TagWriteScreen> createState() => _TagWriteScreenState();
}

class _TagWriteScreenState extends State<TagWriteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _label = TextEditingController();
  final _tagId = TextEditingController();
  final _location = TextEditingController();
  final _passphrase = TextEditingController();
  late final AppServices _services = AppScope.of(context);
  bool _tagIdEdited = false;
  bool _lock = true;
  bool _replace = false;
  bool _prefilled = false;
  bool _sessionOn = false;
  _Stage _stage = _Stage.form;
  String? _message;
  TagWriteResult? _result;

  // Test mode: one simulated blank sticker, kept across retries.
  late final String _simUid =
      '04${List.generate(6, (_) => Random().nextInt(256).toRadixString(16).padLeft(2, '0')).join().toUpperCase()}';
  final _simTag = SimulatedNtag(formatted: false);
  bool _simulated = false;

  bool get _isRewrite => widget.tagId != null;

  @override
  void initState() {
    super.initState();
    if (_isRewrite) _tagId.text = widget.tagId!;
    _label.addListener(() {
      if (!_isRewrite && !_tagIdEdited) _tagId.text = slugify(_label.text);
    });
  }

  @override
  void dispose() {
    if (_sessionOn) _services.nfc.stop();
    for (final c in [_label, _tagId, _location, _passphrase]) {
      c.dispose();
    }
    super.dispose();
  }

  void _prefill(TagInfo? tag) {
    if (_prefilled || tag == null) return;
    _prefilled = true;
    _label.text = tag.label;
    _location.text = tag.location;
  }

  Future<void> _start() async {
    if (!_formKey.currentState!.validate()) return;
    final status = await _services.nfc.status();
    if (!mounted) return;
    if (status != NfcStatus.enabled && _services.simulateNfc) {
      // No NFC here: wait for "Simulate a blank tag".
      setState(() {
        _stage = _Stage.waiting;
        _message = 'Test mode: no NFC here, use "Simulate a blank tag".';
      });
      return;
    }
    if (status != NfcStatus.enabled) {
      setState(() {
        _stage = _Stage.failed;
        _message = status == NfcStatus.disabled
            ? 'Turn on NFC in your phone settings first.'
            : 'This phone has no NFC.';
      });
      return;
    }
    setState(() {
      _stage = _Stage.waiting;
      _message = null;
    });
    if (_sessionOn) return;
    _sessionOn = true;
    await _services.nfc.startWriter(onTag: _onTag, onError: _fail);
  }

  Future<void> _onTag(String uid, TagTransport transport) async {
    if (!mounted || _stage != _Stage.waiting && _stage != _Stage.failed) return;
    setState(() => _stage = _Stage.registering);
    final RegisteredTag reg;
    try {
      reg = await _services.admin.registerTag(
        tagId: _tagId.text.trim(),
        tagUid: uid,
        label: _label.text.trim(),
        location: _location.text.trim(),
        replace: _replace,
      );
    } on AdminFailure catch (e) {
      if (e.reason == 'TAG_ID_TAKEN' && !_replace) return _askReplace();
      return _fail(e);
    } catch (e) {
      return _fail(e);
    }

    if (!mounted) return;
    setState(() => _stage = _Stage.writing);
    try {
      final pass = _passphrase.text;
      final result = await NtagProgrammer(transport).program(
        url: reg.url,
        password: pass.isEmpty ? null : TagPassword.derive(pass, uid),
        lock: _lock,
      );
      HapticFeedback.mediumImpact();
      if (!mounted) return;
      setState(() {
        _stage = _Stage.done;
        _result = result;
      });
      _sessionOn = false;
      await _services.nfc.stop();
    } catch (e) {
      // Registered but not written: tapping again retries the whole thing safely.
      _fail(
        e is TagWriteException
            ? TagWriteException(
                '${e.message} The tag is registered; tap it again to finish.',
              )
            : e,
      );
    }
  }

  Future<void> _askReplace() async {
    if (!mounted) return;
    setState(() => _stage = _Stage.form);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace the existing tag?'),
        content: Text(
          'Tag ID "${_tagId.text.trim()}" belongs to a different physical tag. '
          'Replacing it means the old sticker stops working.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Replace'),
          ),
        ],
      ),
    );
    if (!mounted) return;
    if (ok == true) {
      setState(() {
        _replace = true;
        _stage = _Stage.waiting;
        _message = 'Hold the new tag to the phone again.';
      });
    }
  }

  void _fail(Object e) {
    if (!mounted) return;
    HapticFeedback.heavyImpact();
    setState(() {
      _stage = _Stage.failed;
      _message = switch (e) {
        AdminFailure() => e.message,
        TagWriteException() => e.message,
        NfcReadException() => e.message,
        _ => 'Something went wrong. Tap the tag again.',
      };
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isRewrite ? 'Rewrite tag' : 'Add tag')),
      body: StreamBuilder<AppSettings>(
        stream: _services.admin.watchSettings(),
        builder: (context, settingsSnap) => StreamBuilder<List<TagInfo>>(
          stream: _services.admin.watchTags(),
          builder: (context, tagsSnap) {
            if (_isRewrite) {
              _prefill(
                tagsSnap.data
                    ?.where((t) => t.tagId == widget.tagId)
                    .firstOrNull,
              );
            }
            final base = settingsSnap.data?.tagUrlBase ?? '';
            return _stage == _Stage.form
                ? _buildForm(base)
                : _buildProgress(base);
          },
        ),
      ),
    );
  }

  Widget _buildForm(String base) {
    const gap = SizedBox(height: 16);
    final noBase = base.isEmpty;
    return Form(
      key: _formKey,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (noBase)
            Card(
              key: const Key('tag-no-base'),
              color: Theme.of(context).colorScheme.errorContainer,
              child: ListTile(
                title: const Text('Tag domain not set'),
                subtitle: const Text(
                  'Set the tag domain in Settings before writing tags.',
                ),
                trailing: TextButton(
                  onPressed: () => context.push(Routes.settings),
                  child: const Text('Settings'),
                ),
              ),
            ),
          TextFormField(
            key: const Key('tag-label'),
            controller: _label,
            decoration: const InputDecoration(
              labelText: 'Label',
              hintText: 'Main entrance',
              border: OutlineInputBorder(),
            ),
            validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
          ),
          gap,
          TextFormField(
            key: const Key('tag-id'),
            controller: _tagId,
            enabled: !_isRewrite,
            decoration: InputDecoration(
              labelText: 'Tag ID (in the URL)',
              border: const OutlineInputBorder(),
              helperText: base.isEmpty ? null : '$base${_tagId.text}',
            ),
            onChanged: (_) => setState(() => _tagIdEdited = true),
            validator: (v) =>
                RegExp(r'^[A-Za-z0-9_-]{1,64}$').hasMatch((v ?? '').trim())
                ? null
                : 'Letters, digits, - and _ only',
          ),
          gap,
          TextFormField(
            key: const Key('tag-location'),
            controller: _location,
            decoration: const InputDecoration(
              labelText: 'Location (optional)',
              hintText: 'Ground floor lobby',
              border: OutlineInputBorder(),
            ),
          ),
          SwitchListTile(
            key: const Key('tag-lock'),
            title: const Text('Lock tag with a passphrase'),
            subtitle: const Text(
              'Stops anyone rewriting the sticker. Phones can still read it.',
            ),
            value: _lock,
            onChanged: (v) => setState(() => _lock = v),
          ),
          TextFormField(
            key: const Key('tag-passphrase'),
            controller: _passphrase,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Tag passphrase',
              border: OutlineInputBorder(),
              helperMaxLines: 3,
              helperText:
                  'Not stored anywhere. Use the same one for all office tags and keep it safe: '
                  "you need it to rewrite a locked tag. Leave blank only if you aren't locking.",
            ),
            validator: (v) => _lock && (v ?? '').length < 8
                ? 'At least 8 characters to lock'
                : null,
          ),
          gap,
          FilledButton.icon(
            key: const Key('tag-start'),
            onPressed: noBase ? null : _start,
            icon: const Icon(Icons.nfc),
            label: const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Write tag'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgress(String base) {
    final scheme = Theme.of(context).colorScheme;
    final (
      IconData icon,
      Color? color,
      String title,
      String body,
    ) = switch (_stage) {
      _Stage.waiting => (
        Icons.nfc,
        scheme.primary,
        'Hold the tag to the back of the phone',
        _message ?? 'Keep it there until this screen says done.',
      ),
      _Stage.registering => (
        Icons.cloud_upload_outlined,
        null,
        'Registering…',
        'Keep holding the tag.',
      ),
      _Stage.writing => (Icons.edit, null, 'Writing…', 'Keep holding the tag.'),
      _Stage.done => (
        Icons.check_circle,
        Colors.green.shade700,
        'Tag ready',
        '${_label.text.trim()} · ${_result!.type.name}${_result!.locked ? ' · locked' : ''}'
            '${_simulated ? ' · simulated' : ''}\n$base${_tagId.text.trim()}',
      ),
      _Stage.failed => (
        Icons.error_outline,
        scheme.error,
        'Not finished',
        _message ?? '',
      ),
      _Stage.form => (Icons.nfc, null, '', ''),
    };
    final busy = _stage == _Stage.registering || _stage == _Stage.writing;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          key: Key('tag-stage-${_stage.name}'),
          mainAxisSize: MainAxisSize.min,
          children: [
            busy
                ? const SizedBox.square(
                    dimension: 80,
                    child: CircularProgressIndicator(strokeWidth: 6),
                  )
                : Icon(icon, size: 80, color: color),
            const SizedBox(height: 16),
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(body, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            if (_services.simulateNfc &&
                (_stage == _Stage.waiting || _stage == _Stage.failed)) ...[
              OutlinedButton.icon(
                key: const Key('tag-simulate'),
                onPressed: () {
                  _simulated = true;
                  _onTag(_simUid, _simTag);
                },
                icon: const Icon(Icons.touch_app),
                label: const Text('Simulate a blank tag'),
              ),
              const SizedBox(height: 8),
            ],
            if (_stage == _Stage.done)
              FilledButton(
                onPressed: () => context.pop(),
                child: const Text('Done'),
              )
            else if (!busy)
              TextButton(
                onPressed: () async {
                  _sessionOn = false;
                  await _services.nfc.stop();
                  if (mounted) setState(() => _stage = _Stage.form);
                },
                child: const Text('Back to details'),
              ),
          ],
        ),
      ),
    );
  }
}
