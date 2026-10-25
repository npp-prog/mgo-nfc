import 'package:flutter/material.dart';

import '../app_scope.dart';

class SignOutButton extends StatelessWidget {
  const SignOutButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'Sign out',
    icon: const Icon(Icons.logout),
    onPressed: () async {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Sign out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Sign out'),
            ),
          ],
        ),
      );
      if (confirmed == true && context.mounted) {
        await AppScope.of(context).session.signOut();
      }
    },
  );
}
