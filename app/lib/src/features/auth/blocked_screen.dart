import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../session/session_controller.dart';

/// Shown when the account has no profile, is deactivated, or the profile failed to load.
class BlockedScreen extends StatelessWidget {
  const BlockedScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = AppScope.of(context).session;
    final message = switch (session.blockedReason) {
      BlockedReason.inactive => 'Your account has been deactivated. Contact your admin if this is a mistake.',
      BlockedReason.noProfile => 'Your account is not set up for attendance yet. Ask your admin to add you.',
      BlockedReason.loadFailed || null =>
        'We could not load your profile. Check your connection and try again.',
    };
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.block,
                  size: 64,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  key: const Key('blocked-message'),
                ),
                const SizedBox(height: 24),
                OutlinedButton(
                  onPressed: session.signOut,
                  child: const Text('Sign out'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
