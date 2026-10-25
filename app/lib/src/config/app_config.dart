import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

/// Build-time configuration, set with `--dart-define`.
///
/// Emulator mode (no Firebase project or google-services.json needed):
///   flutter run --dart-define=USE_EMULATORS=true
///   flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=192.168.1.20
///
/// In Chrome on your computer (no phone needed):
///   flutter run -d chrome --dart-define=USE_EMULATORS=true
///
/// The default host is `127.0.0.1` on the web and `10.0.2.2` (the host machine
/// as seen from the Android emulator) on Android. For a USB-connected phone use
/// `adb reverse` and `127.0.0.1` (see README).
class AppConfig {
  const AppConfig({
    required this.useEmulators,
    required this.emulatorHost,
    this.functionsRegion = 'asia-southeast1',
  });

  factory AppConfig.fromEnvironment() {
    const host = String.fromEnvironment('EMULATOR_HOST');
    return AppConfig(
      useEmulators: const bool.fromEnvironment('USE_EMULATORS'),
      emulatorHost: host.isNotEmpty
          ? host
          : (kIsWeb ? '127.0.0.1' : '10.0.2.2'),
    );
  }

  final bool useEmulators;
  final String emulatorHost;
  final String functionsRegion;

  /// Test mode only: offer "simulate tag" buttons so the full flow can be
  /// tried without NFC hardware. Emulator builds can only reach the local
  /// demo project, so this can never touch real attendance.
  bool get simulateNfc => useEmulators;

  static const emulatorProjectId = 'demo-mgo-nfc';
  static const authPort = 9099;
  static const firestorePort = 8080;
  static const functionsPort = 5001;

  /// Placeholder options for the emulator-only demo project. The emulators
  /// accept any API key, so nothing here is a secret.
  static FirebaseOptions get emulatorFirebaseOptions => FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: kIsWeb
        ? '1:000000000000:web:0000000000000000'
        : '1:000000000000:android:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: emulatorProjectId,
    authDomain: kIsWeb ? '$emulatorProjectId.firebaseapp.com' : null,
  );
}
