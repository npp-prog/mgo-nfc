import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app_scope.dart';
import '../../router.dart';
import '../../widgets/sign_out_button.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).session.user;
    // (icon, title, subtitle, route or null while not built yet)
    final sections = <(IconData, String, String, String?)>[
      (
        Icons.dashboard_outlined,
        'Today',
        'Present, late and absent',
        Routes.dashboard,
      ),
      (
        Icons.people_outline,
        'Employees',
        'Add, edit, deactivate',
        Routes.employees,
      ),
      (Icons.nfc, 'Tags', 'Write and register NFC tags', null),
      (Icons.download_outlined, 'Export', 'CSV for payroll', null),
      (
        Icons.settings_outlined,
        'Settings',
        'Late time, time zone, tag URL',
        null,
      ),
      (
        Icons.touch_app_outlined,
        'Check in / out',
        'Your own attendance',
        Routes.home,
      ),
    ];
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
          for (final (icon, title, subtitle, route) in sections)
            ListTile(
              leading: Icon(icon),
              title: Text(title),
              subtitle: Text(subtitle),
              enabled: route != null,
              onTap: route == null
                  ? null
                  : () => route == Routes.home
                        ? context.go(route)
                        : context.push(route),
            ),
        ],
      ),
    );
  }
}
