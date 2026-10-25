import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:mgo_attendance/src/nfc/ndef_uri.dart';
import 'package:mgo_attendance/src/nfc/ntag_programmer.dart';
import 'package:nfc_manager/ndef_record.dart';

import 'package:mgo_attendance/src/nfc/simulated_ntag.dart';

const url = 'https://attendance.example.com/tag/main-entrance';
const uid = '04A1B2C3D4E5F6';

/// Reads the NDEF URL back from the fake tag's memory like a phone would.
String? readUrl(SimulatedNtag tag) {
  final bytes = BytesBuilder();
  for (var p = 4; p < tag.type.cfgPage; p++) {
    bytes.add(tag.page(p));
  }
  final mem = bytes.toBytes();
  expect(mem[0], 0x03, reason: 'NDEF TLV');
  final len = mem[1];
  expect(mem[2 + len], 0xFE, reason: 'terminator TLV');
  return firstUri(
    NdefMessage.decode(Uint8List.fromList(mem.sublist(2, 2 + len))),
  );
}

void main() {
  test('writes the URL to a factory NTAG215 without locking', () async {
    final tag = SimulatedNtag();
    final res = await NtagProgrammer(tag).program(url: url);
    expect(res.type, NtagType.ntag215);
    expect(res.locked, isFalse);
    expect(readUrl(tag), url);
    expect(tag.protected, isFalse);
  });

  test('formats a blank tag (empty capability container)', () async {
    final tag = SimulatedNtag(formatted: false);
    await NtagProgrammer(tag).program(url: url);
    expect(tag.page(3), [0xE1, 0x10, 0x3E, 0x00]);
    expect(readUrl(tag), url);
  });

  test('supports NTAG213 and NTAG216 layouts', () async {
    for (final type in [NtagType.ntag213, NtagType.ntag216]) {
      final tag = SimulatedNtag(type: type, formatted: false);
      final res = await NtagProgrammer(tag).program(
        url: url,
        password: TagPassword.derive('pass', uid),
        lock: true,
      );
      expect(res.type, type);
      expect(readUrl(tag), url);
      expect(tag.auth0, 0x04, reason: type.name);
    }
  });

  test(
    'locks: afterwards writes need the password, reads still work',
    () async {
      final tag = SimulatedNtag();
      final pw = TagPassword.derive('office secret', uid);
      final res = await NtagProgrammer(tag)
          .program(url: url, password: pw, lock: true);
      expect(res.locked, isTrue);
      expect(tag.protected, isTrue);
      expect(tag.auth0, 0x04);
      expect(
        tag.page(tag.type.cfgPage + 1)[0] & 0x80,
        0,
        reason: 'PROT=0: reads stay open',
      );

      // A stranger can't overwrite it.
      tag.reconnect();
      await expectLater(
        tag.transceive(Uint8List.fromList([0xA2, 4, 0, 0, 0, 0])),
        throwsStateError,
      );
      tag.reconnect();
      expect(readUrl(tag), url);
    },
  );

  test('rewrites a locked tag with the right passphrase', () async {
    final tag = SimulatedNtag();
    final pw = TagPassword.derive('office secret', uid);
    await NtagProgrammer(tag).program(url: url, password: pw, lock: true);
    tag.reconnect();

    const newUrl = 'https://attendance.example.com/tag/back-door';
    final res = await NtagProgrammer(tag)
        .program(url: newUrl, password: pw, lock: true);
    expect(res.locked, isTrue);
    expect(readUrl(tag), newUrl);
  });

  test(
    'wrong passphrase or none on a locked tag is refused, tag unchanged',
    () async {
      final tag = SimulatedNtag();
      await NtagProgrammer(tag).program(
        url: url,
        password: TagPassword.derive('right', uid),
        lock: true,
      );

      tag.reconnect();
      await expectLater(
        NtagProgrammer(tag).program(
          url: 'https://x.example/tag/evil',
          password: TagPassword.derive('wrong', uid),
        ),
        throwsA(
          isA<TagWriteException>().having(
            (e) => e.message,
            'message',
            contains('Wrong tag passphrase'),
          ),
        ),
      );
      tag.reconnect();
      await expectLater(
        NtagProgrammer(tag).program(url: 'https://x.example/tag/evil'),
        throwsA(
          isA<TagWriteException>().having(
            (e) => e.message,
            'message',
            contains('password-protected'),
          ),
        ),
      );
      tag.reconnect();
      expect(readUrl(tag), url);
    },
  );

  test('passwords differ per tag and are stable for the same passphrase', () {
    final a = TagPassword.derive('p', '04AAAAAAAAAAAA');
    final b = TagPassword.derive('p', '04BBBBBBBBBBBB');
    expect(a.pwd, isNot(b.pwd));
    expect(TagPassword.derive('p', '04AAAAAAAAAAAA').pwd, a.pwd);
    expect(a.pwd, hasLength(4));
    expect(a.pack, hasLength(2));
  });

  test(
    'tag pulled away mid-write gives a retryable error and is not locked',
    () async {
      final tag = SimulatedNtag(failAfterWrites: 2);
      await expectLater(
        NtagProgrammer(
          tag,
        ).program(url: url, password: TagPassword.derive('p', uid), lock: true),
        throwsA(
          isA<TagWriteException>().having(
            (e) => e.message,
            'message',
            contains('Hold the tag still'),
          ),
        ),
      );
      expect(tag.protected, isFalse);
    },
  );

  test('rejects non-NTAG chips and over-long URLs', () async {
    final notNtag = _Replying([
      0x00,
      0x04,
      0x03,
      0x01,
      0x01,
      0x00,
      0x0B,
      0x03,
    ]); // Ultralight EV1
    await expectLater(
      NtagProgrammer(notNtag).program(url: url),
      throwsA(isA<TagWriteException>()),
    );

    final small = SimulatedNtag(type: NtagType.ntag213);
    await expectLater(
      NtagProgrammer(small)
          .program(url: 'https://attendance.example.com/tag/${'x' * 200}'),
      throwsA(
        isA<TagWriteException>().having(
          (e) => e.message,
          'message',
          contains('too long'),
        ),
      ),
    );
  });

  test('lock without a password is a programming error', () {
    expect(
      () => NtagProgrammer(SimulatedNtag()).program(url: url, lock: true),
      throwsArgumentError,
    );
  });

  test(
    'ndefTlv uses the 3-byte length form for long messages and pads to pages',
    () {
      final short = ndefTlv(Uint8List(10));
      expect(short.sublist(0, 2), [0x03, 10]);
      expect(short.length % 4, 0);
      final long = ndefTlv(Uint8List(300));
      expect(long.sublist(0, 4), [0x03, 0xFF, 0x01, 0x2C]);
      expect(long[4 + 300], 0xFE);
    },
  );
}

class _Replying implements TagTransport {
  _Replying(this.reply);
  final List<int> reply;
  @override
  Future<Uint8List> transceive(Uint8List command) async =>
      Uint8List.fromList(reply);
}
