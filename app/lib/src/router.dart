import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'features/admin/admin_home_screen.dart';
import 'features/auth/blocked_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/employee/history_screen.dart';
import 'features/employee/tap_screen.dart';
import 'session/session_controller.dart';

abstract final class Routes {
  static const splash = '/splash';
  static const login = '/login';
  static const blocked = '/blocked';
  static const home = '/home';
  static const history = '/home/history';
  static const admin = '/admin';
}

/// Where a session in [status] is allowed to be; null = stay on [location].
@visibleForTesting
String? redirectFor(SessionController session, String location) {
  switch (session.status) {
    case SessionStatus.loading:
      return location == Routes.splash ? null : Routes.splash;
    case SessionStatus.signedOut:
      return location == Routes.login ? null : Routes.login;
    case SessionStatus.blocked:
      return location == Routes.blocked ? null : Routes.blocked;
    case SessionStatus.ready:
      final landing = session.isAdmin ? Routes.admin : Routes.home;
      if (const {
        Routes.splash,
        Routes.login,
        Routes.blocked,
      }.contains(location)) {
        return landing;
      }
      // Employees may never reach admin pages.
      if (location.startsWith(Routes.admin) && !session.isAdmin) {
        return Routes.home;
      }
      return null;
  }
}

GoRouter buildRouter(SessionController session) => GoRouter(
  initialLocation: Routes.splash,
  refreshListenable: session,
  redirect: (context, state) => redirectFor(session, state.matchedLocation),
  routes: [
    GoRoute(path: Routes.splash, builder: (_, _) => const SplashScreen()),
    GoRoute(path: Routes.login, builder: (_, _) => const LoginScreen()),
    GoRoute(path: Routes.blocked, builder: (_, _) => const BlockedScreen()),
    GoRoute(
      path: Routes.home,
      builder: (_, _) => const TapScreen(),
      routes: [
        GoRoute(path: 'history', builder: (_, _) => const HistoryScreen()),
      ],
    ),
    GoRoute(path: Routes.admin, builder: (_, _) => const AdminHomeScreen()),
  ],
);
