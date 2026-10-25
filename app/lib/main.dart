import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/app_scope.dart';
import 'src/config/app_config.dart';
import 'src/nfc/nfc_service.dart';
import 'src/services/attendance_repository.dart';
import 'src/services/auth_repository.dart';
import 'src/services/user_repository.dart';
import 'src/session/session_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();

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
          FirebaseFunctions.instanceFor(region: config.functionsRegion),
        ),
      ),
      showEmulatorBanner: config.useEmulators,
    ),
  );
}
