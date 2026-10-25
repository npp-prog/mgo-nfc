import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../widgets/sign_out_button.dart';

/// Employee landing page. NFC tap-to-check-in and history arrive in step 6.
class EmployeeHomeScreen extends StatelessWidget {
  const EmployeeHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = AppScope.of(context).session.user;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
        actions: const [SignOutButton()],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Hello, ${user?.name ?? ''}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(user?.employeeId ?? ''),
              const SizedBox(height: 32),
              const Icon(Icons.nfc, size: 96),
              const SizedBox(height: 16),
              const Text(
                'Tap-to-check-in is coming next.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
