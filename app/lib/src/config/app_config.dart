import 'package:firebase_core/firebase_core.dart';

/// Build-time configuration, set with `--dart-define`.
///
/// Emulator mode (no Firebase project or google-services.json needed):
///   flutter run --dart-define=USE_EMULATORS=true
///   flutter run --dart-define=USE_EMULATORS=true --dart-define=EMULATOR_HOST=192.168.1.20
///
/// `10.0.2.2` is the host machine as seen from the Android emulator. For a
/// physical phone, use your computer's LAN IP (emulators must listen on it,
/// see README).
class AppConfig {
  const AppConfig({
    required this.useEmulators,
    required this.emulatorHost,
    this.functionsRegion = 'asia-southeast1',
  });

  factory AppConfig.fromEnvironment() => const AppConfig(
    useEmulators: bool.fromEnvironment('USE_EMULATORS'),
    emulatorHost: String.fromEnvironment(
      'EMULATOR_HOST',
      defaultValue: '10.0.2.2',
    ),
  );

  final bool useEmulators;
  final String emulatorHost;
  final String functionsRegion;

  static const emulatorProjectId = 'demo-mgo-nfc';
  static const authPort = 9099;
  static const firestorePort = 8080;
  static const functionsPort = 5001;

  /// Placeholder options for the emulator-only demo project. The emulators
  /// accept any API key, so nothing here is a secret.
  static const emulatorFirebaseOptions = FirebaseOptions(
    apiKey: 'demo-api-key',
    appId: '1:000000000000:android:0000000000000000',
    messagingSenderId: '000000000000',
    projectId: emulatorProjectId,
  );
}
