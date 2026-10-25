import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_scope.dart';
import 'src/config/app_config.dart';
import 'src/nfc/nfc_service.dart';
import 'src/services/admin_repository.dart';
import 'src/services/attendance_repository.dart';
import 'src/services/auth_repository.dart';
import 'src/services/file_sharer.dart';
import 'src/services/user_repository.dart';
import 'src/session/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

  if (kIsWeb && !config.useEmulators) {
    // The web build is for trying the app without a phone. It has no
    // production Firebase config yet.
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'The web version only runs in test mode.\n'
                'Start it with --dart-define=USE_EMULATORS=true (see README).',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
    return;
  }

  if (config.useEmulators) {
    await Firebase.initializeApp(options: AppConfig.emulatorFirebaseOptions);
    final host = config.emulatorHost;
    await FirebaseAuth.instance.useAuthEmulator(host, AppConfig.authPort);
    FirebaseFirestore.instance.useFirestoreEmulator(
      host,
      AppConfig.firestorePort,
    );
    FirebaseFunctions.instanceFor(region: config.functionsRegion)
        .useFunctionsEmulator(host, AppConfig.functionsPort);
  } else {
    // Reads android/app/google-services.json (iOS: GoogleService-Info.plist).
    await Firebase.initializeApp();
  }

  final auth = FirebaseAuthRepository(FirebaseAuth.instance);
  final functions = FirebaseFunctions.instanceFor(
    region: config.functionsRegion,
  );
  final session = SessionController(
    auth: auth,
    users: FirestoreUserRepository(FirebaseFirestore.instance),
  );

  runApp(
    MgoAttendanceApp(
      services: AppServices(
        auth: auth,
        session: session,
        nfc: NfcManagerService(),
        attendance: FirebaseAttendanceRepository(
          FirebaseFirestore.instance,
          functions,
        ),
        admin: FirebaseAdminRepository(FirebaseFirestore.instance, functions),
        files: ShareSheetFileSharer(),
        simulateNfc: config.simulateNfc,
      ),
      showEmulatorBanner: config.useEmulators,
    ),
  );
}
