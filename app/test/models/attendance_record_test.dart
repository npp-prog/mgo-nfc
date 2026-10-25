import 'package:flutter_test/flutter_test.dart';
import 'package:mgo_attendance/src/models/attendance_record.dart';
import 'package:mgo_attendance/src/services/attendance_repository.dart';

import '../fakes/fakes.dart';

void main() {
  group('AttendanceDay', () {
    test('groups by date, newest first, taps in time order', () {
      final days = AttendanceDay.group([
        rec('2026-10-26', 17, 0, TapType.checkOut),
        rec('2026-10-27', 8, 0, TapType.checkIn),
        rec('2026-10-26', 7, 50, TapType.checkIn),
      ]);
      expect(days.map((d) => d.date), ['2026-10-27', '2026-10-26']);
      expect(days[1].taps.map((t) => t.type), [
        TapType.checkIn,
        TapType.checkOut,
      ]);
    });

    test('worked time sums in/out pairs and skips the lunch break', () {
      final day = AttendanceDay('2026-10-26', [
        rec('2026-10-26', 7, 50, TapType.checkIn, late: false),
        rec('2026-10-26', 12, 0, TapType.checkOut),
        rec('2026-10-26', 13, 0, TapType.checkIn),
        rec('2026-10-26', 17, 20, TapType.checkOut),
      ]);
      expect(day.worked, const Duration(hours: 8, minutes: 30));
      expect(day.firstIn!.timestamp.hour, 7);
      expect(day.lastOut!.timestamp.hour, 17);
      expect(day.missingCheckOut, isFalse);
    });

    test('open day: missing check-out and late from the first check-in', () {
      final day = AttendanceDay('2026-10-27', [
        rec('2026-10-27', 8, 15, TapType.checkIn, late: true),
      ]);
      expect(day.missingCheckOut, isTrue);
      expect(day.late, isTrue);
      expect(day.worked, Duration.zero);
      expect(day.lastOut, isNull);
    });
  });

  group('tap failures', () {
    test('maps server reasons and details', () {
      final f = tapFailureFrom('failed-precondition', {
        'reason': 'DUPLICATE_TAP',
        'retryAfterSeconds': 95,
        'lastType': 'in',
      });
      expect(f.reason, 'DUPLICATE_TAP');
      expect(f.retryAfterSeconds, 95);
      expect(f.lastType, TapType.checkIn);
      expect(
        f.message,
        'Already recorded your check-in. Wait 1 min 35 s before tapping again.',
      );
    });

    test('falls back on the error code when there are no details', () {
      expect(tapFailureFrom('unavailable', null).reason, 'NETWORK');
      expect(tapFailureFrom('deadline-exceeded', null).reason, 'NETWORK');
      expect(tapFailureFrom('unauthenticated', null).reason, 'UNAUTHENTICATED');
      expect(tapFailureFrom('internal', null).reason, 'UNKNOWN');
    });

    test('every known reason has a specific message', () {
      for (final reason in [
        'DUPLICATE_TAP',
        'TAG_UID_MISMATCH',
        'TAG_NOT_REGISTERED',
        'INVALID_TAG_URL',
        'TAG_INACTIVE',
        'USER_INACTIVE',
        'USER_NOT_FOUND',
        'UNAUTHENTICATED',
        'NETWORK',
        'INVALID_INPUT',
      ]) {
        expect(
          TapFailure(reason).message,
          isNot(TapFailure('UNKNOWN').message),
          reason: reason,
        );
      }
    });

    test('short waits are shown in seconds', () {
      expect(
        const TapFailure('DUPLICATE_TAP', retryAfterSeconds: 30).message,
        contains('30 s'),
      );
      expect(
        const TapFailure('DUPLICATE_TAP', retryAfterSeconds: 120).message,
        contains('2 min'),
      );
    });
  });
}
