import 'package:flutter/widgets.dart';

import 'services/auth_repository.dart';
import 'session/session_controller.dart';

/// Hands app-wide services to the widget tree.
class AppServices {
  const AppServices({required this.auth, required this.session});
  final AuthRepository auth;
  final SessionController session;
}

class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope found in context');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope oldWidget) => services != oldWidget.services;
}
