import 'dart:async';

import 'package:mgo_attendance/src/app_scope.dart';
import 'package:mgo_attendance/src/models/app_settings.dart';
import 'package:mgo_attendance/src/models/app_user.dart';
import 'package:mgo_attendance/src/models/day_summary.dart';
import 'package:mgo_attendance/src/models/tag_info.dart';
import 'package:mgo_attendance/src/services/admin_repository.dart';
import 'package:mgo_attendance/src/session/session_controller.dart';
import 'package:mgo_attendance/src/models/attendance_record.dart';
import 'package:mgo_attendance/src/nfc/nfc_service.dart';
import 'package:mgo_attendance/src/nfc/ntag_programmer.dart';
import 'package:mgo_attendance/src/services/file_sharer.dart';
import 'package:mgo_attendance/src/services/attendance_repository.dart';
import 'package:mgo_attendance/src/services/auth_repository.dart';
import 'package:mgo_attendance/src/services/user_repository.dart';

/// A value stream like Firestore/Auth snapshots: each new listener first gets
/// the current value (if any), then every later change. Nothing is dropped
/// when values are set before anyone listens.
class _Live<T> {
  final _listeners = <StreamController<T>>{};
  bool _hasValue = false;
  late T _value;

  T get value => _value;

  void set(T v) {
    _value = v;
    _hasValue = true;
    for (final c in _listeners) {
      c.add(v);
    }
  }

  void error(Object e) {
    for (final c in _listeners) {
      c.addError(e);
    }
  }

  Stream<T> stream() {
    late final StreamController<T> c;
    c = StreamController<T>(
      onListen: () {
        _listeners.add(c);
        if (_hasValue) c.add(_value);
      },
      onCancel: () => _listeners.remove(c),
    );
    return c.stream;
  }
}

class FakeAuthRepository implements AuthRepository {
  final _live = _Live<AuthIdentity?>()..set(null);

  /// Credentials that sign in successfully: email -> (password, uid).
  final accounts = <String, (String, String)>{};
  bool adminClaim = false;
  int forcedRefreshes = 0;
  final resetRequests = <String>[];
  Completer<void>? signInGate;

  void emit(AuthIdentity? identity) => _live.set(identity);

  @override
  Stream<AuthIdentity?> authStateChanges() => _live.stream();

  @override
  AuthIdentity? get currentIdentity => _live.value;

  @override
  Future<void> signIn({required String email, required String password}) async {
    if (signInGate != null) await signInGate!.future;
    final account = accounts[email.trim()];
    if (account == null || account.$1 != password) {
      throw AuthFailure(messageForAuthError('invalid-credential'));
    }
    emit(AuthIdentity(uid: account.$2, email: email.trim()));
  }

  @override
  Future<void> sendPasswordReset(String email) async =>
      resetRequests.add(email);

  @override
  Future<void> signOut() async => emit(null);

  @override
  Future<bool> hasAdminClaim({bool forceRefresh = false}) async {
    if (forceRefresh) forcedRefreshes++;
    return adminClaim;
  }
}

class FakeUserRepository implements UserRepository {
  final _docs = <String, _Live<AppUser?>>{};

  _Live<AppUser?> _doc(String uid) =>
      _docs.putIfAbsent(uid, _Live<AppUser?>.new);

  void put(AppUser? user, {required String uid}) => _doc(uid).set(user);

  void fail(String uid, Object error) => _doc(uid).error(error);

  @override
  Stream<AppUser?> watchUser(String uid) => _doc(uid).stream();
}

AppUser user({
  String uid = 'u1',
  UserRole role = UserRole.employee,
  bool active = true,
  String name = 'Juan dela Cruz',
  bool trackAttendance = true,
  DateTime? createdAt,
}) => AppUser(
  uid: uid,
  email: '$uid@example.com',
  displayName: name,
  employeeId: 'EMP-$uid',
  role: role,
  active: active,
  trackAttendance: trackAttendance,
  createdAt: createdAt,
);

class FakeNfcService implements NfcService {
  NfcStatus current = NfcStatus.enabled;
  void Function(ScannedTag)? _onTag;
  void Function(Object)? _onError;
  int starts = 0;
  int stops = 0;

  bool get listening => _onTag != null;

  @override
  Future<NfcStatus> status() async => current;

  @override
  Future<void> start({
    required void Function(ScannedTag tag) onTag,
    required void Function(Object error) onError,
  }) async {
    starts++;
    _onTag = onTag;
    _onError = onError;
  }

  Future<void> Function(String, TagTransport)? _onWriterTag;
  void Function(Object)? _onWriterError;
  bool get writing => _onWriterTag != null;

  @override
  Future<void> startWriter({
    required Future<void> Function(String uid, TagTransport transport) onTag,
    required void Function(Object error) onError,
  }) async {
    starts++;
    _onWriterTag = onTag;
    _onWriterError = onError;
  }

  /// Brings a tag into range of a writer session; completes when the app is done with it.
  Future<void> present(String uid, TagTransport tag) => _onWriterTag!(uid, tag);
  void writerError(Object e) => _onWriterError!(e);

  @override
  Future<void> stop() async {
    stops++;
    _onTag = null;
    _onError = null;
    _onWriterTag = null;
    _onWriterError = null;
  }

  void tap(ScannedTag tag) => _onTag!(tag);
  void readError(Object e) => _onError!(e);
}

class FakeAttendanceRepository implements AttendanceRepository {
  final _records = _Live<List<AttendanceRecord>>()..set(const []);
  final sent = <ScannedTag>[];

  /// Next responses to recordTap, in order: a TapResult or an exception.
  final responses = <Object>[];
  Completer<void>? gate;

  void setRecords(List<AttendanceRecord> records) => _records.set(records);

  @override
  Future<TapResult> recordTap(ScannedTag tag) async {
    sent.add(tag);
    if (gate != null) await gate!.future;
    final next = responses.removeAt(0);
    if (next is TapResult) return next;
    throw next;
  }

  @override
  Stream<List<AttendanceRecord>> watchMyRecords(
    String uid, {
    int limit = 200,
  }) => _records.stream();
}

AttendanceRecord rec(
  String date,
  int hour,
  int minute,
  TapType type, {
  bool late = false,
  String tagId = 'main-entrance',
}) {
  final d = DateTime.parse(date);
  return AttendanceRecord(
    id: '$date-$hour-$minute',
    type: type,
    timestamp: DateTime(d.year, d.month, d.day, hour, minute),
    date: date,
    tagId: tagId,
    late: late,
  );
}

class FakeAdminRepository implements AdminRepository {
  final users = _Live<List<AppUser>>()..set(const []);
  final tags = _Live<List<TagInfo>>()..set(const []);
  final settings = _Live<AppSettings>()..set(const AppSettings());
  final _days = <String, _Live<List<DaySummary>>>{};

  final created = <EmployeeDraft>[];
  final updated = <(String, EmployeeDraft)>[];
  final registered = <Map<String, Object?>>[];
  final tagUpdates = <(String, String, String, bool)>[];
  final exports = <(String, String, bool)>[];
  final savedSettings = <AppSettings>[];

  /// If set, the next mutating call throws it (then it is cleared).
  Object? nextError;
  CsvExport exportResult = const CsvExport(
    filename: 'a.csv',
    csv: 'x',
    rowCount: 0,
  );
  RegisteredTag Function(String tagId)? registerResult;

  _Live<List<DaySummary>> _day(String date) =>
      _days.putIfAbsent(date, () => _Live<List<DaySummary>>()..set(const []));
  void setDay(String date, List<DaySummary> s) => _day(date).set(s);

  Future<void> _maybeFail() async {
    final e = nextError;
    nextError = null;
    if (e != null) throw e;
  }

  @override
  Stream<List<AppUser>> watchUsers() => users.stream();
  @override
  Stream<List<DaySummary>> watchDaySummaries(String date) =>
      _day(date).stream();
  @override
  Stream<List<TagInfo>> watchTags() => tags.stream();
  @override
  Stream<AppSettings> watchSettings() => settings.stream();

  @override
  Future<String> createEmployee(EmployeeDraft draft) async {
    await _maybeFail();
    created.add(draft);
    return 'new-uid';
  }

  @override
  Future<void> updateEmployee(String uid, EmployeeDraft draft) async {
    await _maybeFail();
    updated.add((uid, draft));
  }

  @override
  Future<RegisteredTag> registerTag({
    required String tagId,
    required String tagUid,
    required String label,
    required String location,
    bool replace = false,
  }) async {
    await _maybeFail();
    registered.add({
      'tagId': tagId,
      'tagUid': tagUid,
      'label': label,
      'location': location,
      'replace': replace,
    });
    return registerResult?.call(tagId) ??
        RegisteredTag(
          tagId: tagId,
          url: '${settings.value.tagUrlBase}$tagId',
          created: true,
        );
  }

  @override
  Future<void> updateTag(
    String tagId, {
    required String label,
    required String location,
    required bool active,
  }) async {
    await _maybeFail();
    tagUpdates.add((tagId, label, location, active));
  }

  @override
  Future<CsvExport> exportCsv({
    required String from,
    required String to,
    required bool raw,
  }) async {
    await _maybeFail();
    exports.add((from, to, raw));
    return exportResult;
  }

  @override
  Future<void> saveSettings(AppSettings s) async {
    await _maybeFail();
    savedSettings.add(s);
    settings.set(s);
  }
}

class FakeFileSharer implements FileSharer {
  final shared = <(String, String, String)>[];
  @override
  Future<void> shareText({
    required String filename,
    required String content,
    required String mimeType,
  }) async => shared.add((filename, content, mimeType));
}

/// AppServices wired with fakes; pass the ones a test needs to inspect.
AppServices testServices({
  required FakeAuthRepository auth,
  required SessionController session,
  FakeNfcService? nfc,
  FakeAttendanceRepository? attendance,
  FakeAdminRepository? admin,
  FakeFileSharer? files,
}) => AppServices(
  auth: auth,
  session: session,
  nfc: nfc ?? FakeNfcService(),
  attendance: attendance ?? FakeAttendanceRepository(),
  admin: admin ?? FakeAdminRepository(),
  files: files ?? FakeFileSharer(),
);
