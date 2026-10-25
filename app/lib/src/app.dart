import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'app_scope.dart';
import 'router.dart';

class MgoAttendanceApp extends StatefulWidget {
  const MgoAttendanceApp({
    super.key,
    required this.services,
    this.showEmulatorBanner = false,
  });

  final AppServices services;
  final bool showEmulatorBanner;

  @override
  State<MgoAttendanceApp> createState() => _MgoAttendanceAppState();
}

class _MgoAttendanceAppState extends State<MgoAttendanceApp> {
  late final GoRouter _router = buildRouter(widget.services.session);

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1B5E20));
    final app = MaterialApp.router(
      title: 'MGO Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: scheme, useMaterial3: true),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1B5E20),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      routerConfig: _router,
      builder: widget.showEmulatorBanner
          ? (context, child) => Banner(
              message: 'EMULATOR',
              location: BannerLocation.topEnd,
              child: child!,
            )
          : null,
    );
    return AppScope(services: widget.services, child: app);
  }
}
