import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/app_settings.dart';
import '../models/app_user.dart';
import '../models/day_summary.dart';
import '../models/tag_info.dart';
import 'firestore_convert.dart';

/// Rejected admin action, with the backend's reason code.
class AdminFailure implements Exception {
  const AdminFailure(this.reason, this.serverMessage, {this.issues = const []});

  factory AdminFailure.from(String code, String? message, Object? details) {
    final map = details is Map ? details : const {};
    final issues = [
      for (final i in (map['issues'] as List? ?? const []))
        if (i is Map) '${i['path'] ?? ''}: ${i['message'] ?? ''}',
    ];
    final reason =
        map['reason'] as String? ??
        switch (code) {
          'unavailable' || 'deadline-exceeded' => 'NETWORK',
          'permission-denied' => 'NOT_ADMIN',
          _ => 'UNKNOWN',
        };
    return AdminFailure(reason, message ?? '', issues: issues);
  }

  final String reason;
  final String serverMessage;
  final List<String> issues;

  String get message => switch (reason) {
    'EMAIL_EXISTS' => 'An account with this email already exists.',
    'EMPLOYEE_ID_EXISTS' => 'This employee ID is already used by someone else.',
    'SELF_LOCKOUT' => "You can't demote or deactivate your own account.",
    'NOT_ADMIN' =>
      'Admin access required. Sign out and back in if you were just promoted.',
    'TAG_UID_TAKEN' =>
      serverMessage.isNotEmpty
          ? serverMessage
          : 'This physical tag is already registered.',
    'TAG_ID_TAKEN' => 'This tag ID is already used by another physical tag.',
    'TAG_URL_BASE_NOT_SET' =>
      'Set the tag URL in Settings before registering tags.',
    'NETWORK' => 'No connection to the server. Try again.',
    'INVALID_INPUT' =>
      issues.isNotEmpty
          ? 'Please fix: ${issues.join('; ')}'
          : 'Some fields are invalid.',
    _ =>
      serverMessage.isNotEmpty
          ? serverMessage
          : 'Something went wrong. Try again.',
  };

  @override
  String toString() => 'AdminFailure($reason)';
}

class EmployeeDraft {
  const EmployeeDraft({
    required this.displayName,
    required this.employeeId,
    required this.role,
    required this.trackAttendance,
    this.email,
    this.password,
    this.active,
  });

  final String displayName;
  final String employeeId;
  final UserRole role;
  final bool trackAttendance;

  /// Create only.
  final String? email;

  /// Required on create; on edit, set only to reset the password.
  final String? password;

  /// Edit only.
  final bool? active;
}

class RegisteredTag {
  const RegisteredTag({
    required this.tagId,
    required this.url,
    required this.created,
  });
  final String tagId;
  final String url;
  final bool created;
}

class CsvExport {
  const CsvExport({
    required this.filename,
    required this.csv,
    required this.rowCount,
  });
  final String filename;
  final String csv;
  final int rowCount;
}

abstract class AdminRepository {
  Stream<List<AppUser>> watchUsers();
  Stream<List<DaySummary>> watchDaySummaries(String date);
  Stream<List<TagInfo>> watchTags();
  Stream<AppSettings> watchSettings();

  Future<String> createEmployee(EmployeeDraft draft);
  Future<void> updateEmployee(String uid, EmployeeDraft draft);

  Future<RegisteredTag> registerTag({
    required String tagId,
    required String tagUid,
    required String label,
    required String location,
    bool replace = false,
  });
  Future<void> updateTag(
    String tagId, {
    required String label,
    required String location,
    required bool active,
  });

  Future<CsvExport> exportCsv({
    required String from,
    required String to,
    required bool raw,
  });
  Future<void> saveSettings(AppSettings settings);
}

class FirebaseAdminRepository implements AdminRepository {
  FirebaseAdminRepository(this._db, this._functions);
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    try {
      final res = await _functions
          .httpsCallable(
            name,
            options: HttpsCallableOptions(
              timeout: const Duration(seconds: 120),
            ),
          )
          .call<Map<String, dynamic>>(data);
      return res.data;
    } on FirebaseFunctionsException catch (e) {
      throw AdminFailure.from(e.code, e.message, e.details);
    }
  }

  @override
  Stream<List<AppUser>> watchUsers() => _db
      .collection('users')
      .snapshots()
      .map(
        (s) =>
            s.docs
                .map((d) => AppUser.fromMap(d.id, firestoreToPlain(d.data())))
                .toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              ),
      );

  @override
  Stream<List<DaySummary>> watchDaySummaries(String date) => _db
      .collection('attendanceDays')
      .where('date', isEqualTo: date)
      .snapshots()
      .map(
        (s) => s.docs
            .map((d) => DaySummary.fromMap(firestoreToPlain(d.data())))
            .toList(),
      );

  @override
  Stream<List<TagInfo>> watchTags() => _db
      .collection('tags')
      .snapshots()
      .map(
        (s) =>
            s.docs
                .map((d) => TagInfo.fromMap(d.id, firestoreToPlain(d.data())))
                .toList()
              ..sort(
                (a, b) =>
                    a.label.toLowerCase().compareTo(b.label.toLowerCase()),
              ),
      );

  @override
  Stream<AppSettings> watchSettings() => _db
      .doc('settings/app')
      .snapshots()
      .map((s) => AppSettings.fromMap(s.data()));

  @override
  Future<String> createEmployee(EmployeeDraft d) async {
    final res = await _call('createEmployee', {
      'email': d.email,
      'password': d.password,
      'displayName': d.displayName,
      'employeeId': d.employeeId,
      'role': d.role.name,
      'trackAttendance': d.trackAttendance,
    });
    return res['uid'] as String;
  }

  @override
  Future<void> updateEmployee(String uid, EmployeeDraft d) => _call(
    'updateEmployee',
    {
      'uid': uid,
      'displayName': d.displayName,
      'employeeId': d.employeeId,
      'role': d.role.name,
      'trackAttendance': d.trackAttendance,
      'active': ?d.active,
      if (d.password != null && d.password!.isNotEmpty) 'password': d.password,
    },
  );

  @override
  Future<RegisteredTag> registerTag({
    required String tagId,
    required String tagUid,
    required String label,
    required String location,
    bool replace = false,
  }) async {
    final res = await _call('registerTag', {
      'tagId': tagId,
      'tagUid': tagUid,
      'label': label,
      'location': location,
      'replace': replace,
    });
    return RegisteredTag(
      tagId: res['tagId'] as String,
      url: res['url'] as String,
      created: res['created'] == true,
    );
  }

  @override
  Future<void> updateTag(
    String tagId, {
    required String label,
    required String location,
    required bool active,
  }) => _db.doc('tags/$tagId').update({
    'label': label,
    'location': location,
    'active': active,
  });

  @override
  Future<CsvExport> exportCsv({
    required String from,
    required String to,
    required bool raw,
  }) async {
    final res = await _call('exportAttendanceCsv', {
      'from': from,
      'to': to,
      'format': raw ? 'raw' : 'daily',
    });
    return CsvExport(
      filename: res['filename'] as String,
      csv: res['csv'] as String,
      rowCount: (res['rowCount'] as num).toInt(),
    );
  }

  @override
  Future<void> saveSettings(AppSettings settings) =>
      _db.doc('settings/app').set(settings.toMap());
}
