import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../widgets/sign_out_button.dart';

/// Admin landing page. Each section is implemented in step 7.
class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  static const _sections = [
    (Icons.dashboard_outlined, 'Today', 'Present, late and absent'),
    (Icons.people_outline, 'Employees', 'Add, edit, deactivate'),
    (Icons.nfc, 'Tags', 'Write and register NFC tags'),
    (Icons.download_outlined, 'Export', 'CSV for payroll'),
    (Icons.settings_outlined, 'Settings', 'Late time, time zone, tag URL'),
  ];

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).session.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: const [SignOutButton()],
      ),
      body: ListView(
        children: [
          ListTile(
            title: Text(user?.name ?? ''),
            subtitle: Text('${user?.email ?? ''} · Admin'),
          ),
          const Divider(),
          for (final (icon, title, subtitle) in _sections)
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              enabled: false,
            ),
        ],
      ),
    );
  }
}
