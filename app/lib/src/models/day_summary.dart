/// `attendanceDays/{uid}_{date}`, maintained by `recordAttendance`.
class DaySummary {
  const DaySummary({
    required this.userId,
    required this.date,
    this.firstIn,
    this.lastOut,
    this.lastTapAt,
    this.lastIsIn = false,
    this.tapCount = 0,
    this.late = false,
  });

  factory DaySummary.fromMap(Map<String, dynamic> d) => DaySummary(
    userId: d['userId'] as String? ?? '',
    date: d['date'] as String? ?? '',
    firstIn: d['firstIn'] as DateTime?,
    lastOut: d['lastOut'] as DateTime?,
    lastTapAt: d['lastTapAt'] as DateTime?,
    lastIsIn: d['lastType'] == 'in',
    tapCount: (d['tapCount'] as num?)?.toInt() ?? 0,
    late: d['late'] == true,
  );

  final String userId;
  final String date;
  final DateTime? firstIn;
  final DateTime? lastOut;
  final DateTime? lastTapAt;

  /// True when the last tap was a check-in, i.e. the person is still in.
  final bool lastIsIn;
  final int tapCount;
  final bool late;
}
