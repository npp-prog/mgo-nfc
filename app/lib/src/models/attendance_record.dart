enum TapType {
  checkIn,
  checkOut;

  static TapType parse(Object? v) =>
      v == 'out' ? TapType.checkOut : TapType.checkIn;
}

/// One tap from `attendance/{id}`.
class AttendanceRecord {
  const AttendanceRecord({
    required this.id,
    required this.type,
    required this.timestamp,
    required this.date,
    required this.tagId,
    required this.late,
  });

  final String id;
  final TapType type;
  final DateTime timestamp;

  /// Office-local calendar day (YYYY-MM-DD), as decided by the server.
  final String date;
  final String tagId;
  final bool late;
}

/// One office day built from that day's taps.
class AttendanceDay {
  AttendanceDay(this.date, List<AttendanceRecord> taps)
    : taps = [...taps]..sort((a, b) => a.timestamp.compareTo(b.timestamp));

  final String date;
  final List<AttendanceRecord> taps;

  AttendanceRecord? get firstIn =>
      taps.where((t) => t.type == TapType.checkIn).firstOrNull;
  AttendanceRecord? get lastOut =>
      taps.where((t) => t.type == TapType.checkOut).lastOrNull;
  bool get late => firstIn?.late ?? false;
  bool get missingCheckOut =>
      taps.isNotEmpty && taps.last.type == TapType.checkIn;

  /// Sum of check-in -> check-out pairs (same rule as the payroll export).
  Duration get worked {
    var total = Duration.zero;
    DateTime? openIn;
    for (final t in taps) {
      if (t.type == TapType.checkIn) {
        openIn = t.timestamp;
      } else if (openIn != null) {
        total += t.timestamp.difference(openIn);
        openIn = null;
      }
    }
    return total;
  }

  /// Groups records by office day, newest day first.
  static List<AttendanceDay> group(Iterable<AttendanceRecord> records) {
    final byDate = <String, List<AttendanceRecord>>{};
    for (final r in records) {
      byDate.putIfAbsent(r.date, () => []).add(r);
    }
    final days = [
      for (final e in byDate.entries) AttendanceDay(e.key, e.value),
    ];
    days.sort((a, b) => b.date.compareTo(a.date));
    return days;
  }
}

/// Successful tap, as returned by `recordAttendance`.
class TapResult {
  const TapResult({
    required this.type,
    required this.timestamp,
    required this.late,
    required this.tagLabel,
  });

  final TapType type;
  final DateTime timestamp;
  final bool late;
  final String tagLabel;
}

/// Rejected tap with the server's machine-readable reason.
class TapFailure implements Exception {
  const TapFailure(this.reason, {this.retryAfterSeconds, this.lastType});

  /// e.g. DUPLICATE_TAP, TAG_UID_MISMATCH; see the backend README.
  final String reason;
  final int? retryAfterSeconds;
  final TapType? lastType;

  String get message => switch (reason) {
    'DUPLICATE_TAP' =>
      'Already recorded${lastType == null ? '' : ' your ${lastType == TapType.checkIn ? 'check-in' : 'check-out'}'}. '
          'Wait ${_wait(retryAfterSeconds)} before tapping again.',
    'TAG_UID_MISMATCH' => 'This tag could not be verified. Please use an official office tag and tell your admin.',
    'TAG_NOT_REGISTERED' ||
    'INVALID_TAG_URL' => 'This is not an office attendance tag.',
    'TAG_INACTIVE' =>
      'This tag has been disabled. Please use another entrance tag.',
    'USER_INACTIVE' => 'Your account is deactivated. Contact your admin.',
    'USER_NOT_FOUND' =>
      'Your account is not set up for attendance. Contact your admin.',
    'UNAUTHENTICATED' => 'Your session expired. Please sign in again.',
    'NETWORK' =>
      'No connection to the server. Check your internet and tap again.',
    'INVALID_INPUT' =>
      'The tag could not be read properly. Hold the phone still and try again.',
    _ => 'Something went wrong. Please tap again.',
  };

  static String _wait(int? seconds) {
    if (seconds == null || seconds <= 0) return 'a moment';
    if (seconds < 60) return '$seconds s';
    final m = seconds ~/ 60, s = seconds % 60;
    return s == 0 ? '$m min' : '$m min $s s';
  }

  @override
  String toString() => 'TapFailure($reason)';
}
