import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/attendance_record.dart';
import '../nfc/nfc_service.dart';

abstract class AttendanceRepository {
  /// Sends a tap to `recordAttendance`. Throws [TapFailure] when rejected.
  Future<TapResult> recordTap(ScannedTag tag);

  /// The user's most recent taps, newest first, updated live.
  Stream<List<AttendanceRecord>> watchMyRecords(String uid, {int limit = 200});
}

class FirebaseAttendanceRepository implements AttendanceRepository {
  FirebaseAttendanceRepository(this._db, this._functions);
  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;

  @override
  Future<TapResult> recordTap(ScannedTag tag) async {
    try {
      final res = await _functions
          .httpsCallable(
            'recordAttendance',
            options: HttpsCallableOptions(timeout: const Duration(seconds: 20)),
          )
          .call<Map<String, dynamic>>({
            'tagUid': tag.uid,
            'tagUrl': tag.url ?? '',
          });
      final d = res.data;
      return TapResult(
        type: TapType.parse(d['type']),
        timestamp: DateTime.parse(d['timestamp'] as String).toLocal(),
        late: d['late'] == true,
        tagLabel: d['tagLabel'] as String? ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      throw tapFailureFrom(e.code, e.details);
    }
  }

  @override
  Stream<List<AttendanceRecord>> watchMyRecords(
    String uid, {
    int limit = 200,
  }) => _db
      .collection('attendance')
      .where('userId', isEqualTo: uid)
      .orderBy('timestamp', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(_fromDoc).toList());

  static AttendanceRecord _fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) {
    final data = d.data();
    return AttendanceRecord(
      id: d.id,
      type: TapType.parse(data['type']),
      // Pending server writes have no timestamp yet; never true here since
      // only Cloud Functions write attendance, but stay defensive.
      timestamp: (data['timestamp'] as Timestamp?)?.toDate() ?? DateTime.now(),
      date: data['date'] as String? ?? '',
      tagId: data['tagId'] as String? ?? '',
      late: data['late'] == true,
    );
  }
}

/// Maps a callable error (code + details) to a [TapFailure].
TapFailure tapFailureFrom(String code, Object? details) {
  final map = details is Map ? details : const {};
  final reason =
      map['reason'] as String? ??
      switch (code) {
        'unavailable' || 'deadline-exceeded' => 'NETWORK',
        'unauthenticated' => 'UNAUTHENTICATED',
        _ => 'UNKNOWN',
      };
  final last = map['lastType'];
  return TapFailure(
    reason,
    retryAfterSeconds: (map['retryAfterSeconds'] as num?)?.toInt(),
    lastType: last == null ? null : TapType.parse(last),
  );
}
