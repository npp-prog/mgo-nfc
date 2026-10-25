import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgo_attendance/src/nfc/ndef_uri.dart';
import 'package:nfc_manager/ndef_record.dart';

void main() {
  group('URI records', () {
    test('https URL uses prefix code 4 and round-trips', () {
      const url = 'https://attendance.example.com/tag/main-entrance';
      final r = encodeUriRecord(url);
      expect(r.typeNameFormat, TypeNameFormat.wellKnown);
      expect(r.type, [0x55]);
      expect(r.payload.first, 4);
      expect(
        utf8.decode(r.payload.sublist(1)),
        'attendance.example.com/tag/main-entrance',
      );
      expect(decodeUriRecord(r), url);
    });

    test('prefers the longest prefix (https://www.)', () {
      final r = encodeUriRecord('https://www.example.com/tag/x');
      expect(r.payload.first, 2);
      expect(decodeUriRecord(r), 'https://www.example.com/tag/x');
    });

    test('survives full NDEF encode/decode', () {
      const url = 'https://attendance.example.com/tag/back-door';
      final bytes = NdefMessage(records: [encodeUriRecord(url)]).encode();
      expect(firstUri(NdefMessage.decode(bytes)), url);
    });

    test('reads absolute-URI records', () {
      final r = NdefRecord(
        typeNameFormat: TypeNameFormat.absoluteUri,
        type: Uint8List.fromList(utf8.encode('https://x.example/tag/a')),
        identifier: Uint8List(0),
        payload: Uint8List(0),
      );
      expect(decodeUriRecord(r), 'https://x.example/tag/a');
    });

    test('ignores non-URI records and finds the first URI', () {
      final text = NdefRecord(
        typeNameFormat: TypeNameFormat.wellKnown,
        type: Uint8List.fromList([0x54]),
        identifier: Uint8List(0),
        payload: Uint8List.fromList([2, ...utf8.encode('enhello')]),
      );
      expect(decodeUriRecord(text), isNull);
      expect(
        firstUri(
          NdefMessage(
            records: [text, encodeUriRecord('https://a.example/tag/b')],
          ),
        ),
        'https://a.example/tag/b',
      );
      expect(firstUri(null), isNull);
    });

    test('rejects an unknown prefix code', () {
      final r = NdefRecord(
        typeNameFormat: TypeNameFormat.wellKnown,
        type: Uint8List.fromList([0x55]),
        identifier: Uint8List(0),
        payload: Uint8List.fromList([0xFE, 0x41]),
      );
      expect(decodeUriRecord(r), isNull);
    });
  });

  test('formatTagUid is uppercase hex without separators', () {
    expect(
      formatTagUid([0x04, 0xa1, 0xb2, 0x0c, 0xd4, 0xe5, 0xf6]),
      '04A1B20CD4E5F6',
    );
  });
}
