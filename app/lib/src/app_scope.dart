import 'package:flutter/widgets.dart';

import 'nfc/nfc_service.dart';
import 'services/admin_repository.dart';
import 'services/attendance_repository.dart';
import 'services/auth_repository.dart';
import 'services/file_sharer.dart';
import 'session/session_controller.dart';

/// Hands app-wide services to the widget tree.
class AppServices {
  const AppServices({
    required this.auth,
    required this.session,
    required this.nfc,
    required this.attendance,
    required this.admin,
    required this.files,
    this.simulateNfc = false,
  });
  final AuthRepository auth;
  final SessionController session;
  final NfcService nfc;
  final AttendanceRepository attendance;
  final AdminRepository admin;
  final FileSharer files;

  /// Test mode: show "simulate tag" buttons (see AppConfig.simulateNfc).
  final bool simulateNfc;
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
