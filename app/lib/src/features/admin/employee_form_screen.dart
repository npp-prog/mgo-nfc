import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../models/app_user.dart';
import '../../services/admin_repository.dart';

/// Create (uid == null) or edit an employee.
class EmployeeFormScreen extends StatelessWidget {
  const EmployeeFormScreen({super.key, this.uid});
  final String? uid;

  @override
  Widget build(BuildContext context) {
    if (uid == null) return const _EmployeeForm(existing: null);
    return StreamBuilder<List<AppUser>>(
      stream: AppScope.of(context).admin.watchUsers(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final user = snap.data!.where((u) => u.uid == uid).firstOrNull;
        if (user == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const Center(child: Text('Employee not found.')),
          );
        }
        return _EmployeeForm(key: ValueKey(uid), existing: user);
      },
    );
  }
}

class _EmployeeForm extends StatefulWidget {
  const _EmployeeForm({super.key, required this.existing});
  final AppUser? existing;

  @override
  State<_EmployeeForm> createState() => _EmployeeFormState();
}

class _EmployeeFormState extends State<_EmployeeForm> {
  final _formKey = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.existing?.displayName);
  late final _email = TextEditingController(text: widget.existing?.email);
  late final _employeeId = TextEditingController(
    text: widget.existing?.employeeId,
  );
  final _password = TextEditingController();
  late UserRole _role = widget.existing?.role ?? UserRole.employee;
  late bool _track = widget.existing?.trackAttendance ?? true;
  late bool _active = widget.existing?.active ?? true;
  bool _busy = false;
  String? _error;

  bool get _isNew => widget.existing == null;

  @override
  void dispose() {
    for (final c in [_name, _email, _employeeId, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_busy || !_formKey.currentState!.validate()) return;
    final services = AppScope.of(context);
    final me = services.session.user?.uid;
    if (!_isNew &&
        widget.existing!.uid == me &&
        (!_active || _role != UserRole.admin)) {
      setState(
        () => _error = "You can't demote or deactivate your own account.",
      );
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final draft = EmployeeDraft(
      displayName: _name.text.trim(),
      employeeId: _employeeId.text.trim(),
      role: _role,
      trackAttendance: _track,
      email: _isNew ? _email.text.trim() : null,
      password: _password.text.isEmpty ? null : _password.text,
      active: _isNew ? null : _active,
    );
    try {
      if (_isNew) {
        await services.admin.createEmployee(draft);
      } else {
        await services.admin.updateEmployee(widget.existing!.uid, draft);
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _isNew
                ? 'Added ${draft.displayName}'
                : 'Saved ${draft.displayName}',
          ),
        ),
      );
      context.pop();
    } on AdminFailure catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Something went wrong. Try again.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: 16);
    return Scaffold(
      appBar: AppBar(title: Text(_isNew ? 'Add employee' : 'Edit employee')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              key: const Key('field-name'),
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Full name',
                border: OutlineInputBorder(),
              ),
              textCapitalization: TextCapitalization.words,
              validator: (v) => (v ?? '').trim().isEmpty ? 'Required' : null,
            ),
            gap,
            TextFormField(
              key: const Key('field-email'),
              controller: _email,
              enabled: _isNew,
              decoration: InputDecoration(
                labelText: 'Email (sign-in)',
                border: const OutlineInputBorder(),
                helperText: _isNew ? null : 'Email cannot be changed',
              ),
              keyboardType: TextInputType.emailAddress,
              validator: (v) =>
                  !_isNew ||
                      RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                          .hasMatch((v ?? '').trim())
                  ? null
                  : 'Enter a valid email',
            ),
            gap,
            TextFormField(
              key: const Key('field-employee-id'),
              controller: _employeeId,
              decoration: const InputDecoration(
                labelText: 'Employee ID',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  RegExp(r'^[A-Za-z0-9_-]{1,32}$').hasMatch((v ?? '').trim())
                  ? null
                  : 'Letters, digits, - and _ only',
            ),
            gap,
            TextFormField(
              key: const Key('field-password'),
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(
                labelText: _isNew
                    ? 'Initial password'
                    : 'New password (leave blank to keep)',
                border: const OutlineInputBorder(),
                helperText: 'At least 8 characters. Share it privately; they can reset it later.',
              ),
              validator: (v) {
                final p = v ?? '';
                if (_isNew && p.isEmpty) return 'Required';
                if (p.isNotEmpty && p.length < 8) {
                  return 'At least 8 characters';
                }
                return null;
              },
            ),
            gap,
            DropdownButtonFormField<UserRole>(
              key: const Key('field-role'),
              initialValue: _role,
              decoration: const InputDecoration(
                labelText: 'Role',
                border: OutlineInputBorder(),
              ),
              items: const [
                DropdownMenuItem(
                  value: UserRole.employee,
                  child: Text('Employee'),
                ),
                DropdownMenuItem(value: UserRole.admin, child: Text('Admin')),
              ],
              onChanged: (v) => setState(() => _role = v!),
            ),
            SwitchListTile(
              key: const Key('field-track'),
              title: const Text('Track attendance'),
              subtitle: const Text(
                'Off for owners or remote staff: never counted absent, taps still recorded.',
              ),
              value: _track,
              onChanged: (v) => setState(() => _track = v),
            ),
            if (!_isNew)
              SwitchListTile(
                key: const Key('field-active'),
                title: const Text('Active'),
                subtitle: const Text(
                  'Deactivated people cannot sign in. Their history is kept.',
                ),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
            if (_error != null) ...[
              gap,
              Text(
                _error!,
                key: const Key('form-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            gap,
            FilledButton(
              key: const Key('form-save'),
              onPressed: _busy ? null : _save,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _busy
                    ? const SizedBox.square(
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_isNew ? 'Add employee' : 'Save'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
