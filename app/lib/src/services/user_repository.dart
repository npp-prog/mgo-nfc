import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/app_user.dart';

abstract class UserRepository {
  /// Emits the profile, or null if `users/{uid}` does not exist.
  Stream<AppUser?> watchUser(String uid);
}

class FirestoreUserRepository implements UserRepository {
  FirestoreUserRepository(this._db);
  final FirebaseFirestore _db;

  @override
  Stream<AppUser?> watchUser(String uid) => _db
      .doc('users/$uid')
      .snapshots()
      .map((s) => s.exists ? AppUser.fromMap(s.id, s.data()!) : null);
}
