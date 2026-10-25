import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:nfc_manager/ndef_record.dart';

import 'ndef_uri.dart';

/// Sends one raw NFC-A command to the tag in the field and returns the reply.
abstract class TagTransport {
  Future<Uint8List> transceive(Uint8List command);
}

class TagWriteException implements Exception {
  const TagWriteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// NTAG21x memory layout per chip.
class NtagType {
  const NtagType._(this.name, this.cfgPage, this.ccSize, this.userBytes);
  final String name;

  /// First configuration page (CFG0; CFG1, PWD and PACK follow).
  final int cfgPage;

  /// Capability Container data-area size byte (CC byte 2).
  final int ccSize;
  final int userBytes;

  static const ntag213 = NtagType._('NTAG213', 0x29, 0x12, 144);
  static const ntag215 = NtagType._('NTAG215', 0x83, 0x3E, 504);
  static const ntag216 = NtagType._('NTAG216', 0xE3, 0x6D, 888);

  /// From a GET_VERSION response (vendor NXP, product NTAG, storage size byte).
  static NtagType? fromVersion(List<int> v) {
    if (v.length < 8 || v[1] != 0x04 || v[2] != 0x04) return null;
    return switch (v[6]) {
      0x0F => ntag213,
      0x11 => ntag215,
      0x13 => ntag216,
      _ => null,
    };
  }
}

/// 4-byte PWD + 2-byte PACK for one tag, derived from the admin's passphrase
/// and the tag UID. Nothing is stored: the same passphrase re-derives it, and
/// a password sniffed from one tag doesn't unlock the others.
class TagPassword {
  TagPassword._(this.pwd, this.pack);

  factory TagPassword.derive(String passphrase, String tagUid) {
    final digest = sha256
        .convert(utf8.encode('mgo-nfc-tag-v1|$tagUid|$passphrase'))
        .bytes;
    return TagPassword._(
      Uint8List.fromList(digest.sublist(0, 4)),
      Uint8List.fromList(digest.sublist(4, 6)),
    );
  }

  final Uint8List pwd;
  final Uint8List pack;
}

class TagWriteResult {
  const TagWriteResult({required this.type, required this.locked});
  final NtagType type;
  final bool locked;
}

/// Writes the attendance URL to an NTAG213/215/216 with raw commands and
/// optionally enables write protection (password needed to change pages 4+).
///
/// Raw commands keep everything in one connection, so a protected tag can be
/// authenticated and rewritten. Reading stays open, so phones can still read
/// the URL and UID.
class NtagProgrammer {
  NtagProgrammer(this._t);
  final TagTransport _t;

  static const _getVersion = 0x60;
  static const _read = 0x30;
  static const _write = 0xA2;
  static const _pwdAuth = 0x1B;
  static const _ack = 0x0A;
  static const _firstUserPage = 4;
  static const _auth0Protect = 0x04;

  Future<TagWriteResult> program({
    required String url,
    TagPassword? password,
    bool lock = false,
  }) async {
    if (lock && password == null) {
      throw ArgumentError('lock requires a password');
    }

    final type = NtagType.fromVersion(
      await _cmd([_getVersion], 'read the chip type'),
    );
    if (type == null) {
      throw const TagWriteException(
        'Unsupported tag. Use NTAG213, NTAG215 or NTAG216 stickers.',
      );
    }

    final cfg = await _cmd([_read, type.cfgPage], 'read the tag configuration');
    final cfg0 = cfg.sublist(0, 4);
    final cfg1 = cfg.sublist(4, 8);
    final alreadyProtected = cfg0[3] <= type.cfgPage + 3;

    if (alreadyProtected) {
      if (password == null) {
        throw const TagWriteException(
          'This tag is password-protected. Turn on "Lock" and enter the tag passphrase.',
        );
      }
      await _authenticate(password);
    }

    // Capability Container (page 3) must mark the tag as NDEF. It is OTP
    // (bits can only be set), so only write it when blank.
    final cc = await _cmd([_read, 3], 'read the tag');
    if (cc[0] != 0xE1) {
      if (cc.take(4).any((b) => b != 0)) {
        throw const TagWriteException(
          'This tag was formatted for something else and cannot be reused.',
        );
      }
      await _writePage(3, [0xE1, 0x10, type.ccSize, 0x00]);
    }

    final tlv = ndefTlv(NdefMessage(records: [encodeUriRecord(url)]).encode());
    if (tlv.length > type.userBytes) {
      throw TagWriteException('The URL is too long for ${type.name}.');
    }
    for (var i = 0; i < tlv.length; i += 4) {
      await _writePage(_firstUserPage + i ~/ 4, tlv.sublist(i, i + 4));
    }

    // Read back the first pages to catch a tag pulled away mid-write.
    final check = await _cmd([_read, _firstUserPage], 'verify the tag');
    for (var i = 0; i < 16 && i < tlv.length; i++) {
      if (check[i] != tlv[i]) {
        throw const TagWriteException(
          'Verification failed. Hold the tag still and try again.',
        );
      }
    }

    if (lock && !alreadyProtected) {
      await _writePage(type.cfgPage + 2, password!.pwd);
      await _writePage(type.cfgPage + 3, [
        password.pack[0],
        password.pack[1],
        0,
        0,
      ]);
      // CFG1: clear PROT (bit 7) so only writes are protected, not reads.
      await _writePage(type.cfgPage + 1, [
        cfg1[0] & 0x7F,
        cfg1[1],
        cfg1[2],
        cfg1[3],
      ]);
      // CFG0 last: AUTH0 = first protected page. This switches protection on.
      await _writePage(type.cfgPage, [
        cfg0[0],
        cfg0[1],
        cfg0[2],
        _auth0Protect,
      ]);
    }
    return TagWriteResult(type: type, locked: alreadyProtected || lock);
  }

  Future<void> _authenticate(TagPassword password) async {
    Uint8List res;
    try {
      res = await _t.transceive(
        Uint8List.fromList([_pwdAuth, ...password.pwd]),
      );
    } catch (_) {
      throw const TagWriteException('Wrong tag passphrase for this tag.');
    }
    if (res.length < 2 ||
        res[0] != password.pack[0] ||
        res[1] != password.pack[1]) {
      throw const TagWriteException('Wrong tag passphrase for this tag.');
    }
  }

  Future<void> _writePage(int page, List<int> data) async {
    assert(data.length == 4);
    Uint8List res;
    try {
      res = await _t.transceive(Uint8List.fromList([_write, page, ...data]));
    } catch (e) {
      throw TagWriteException(
        'Writing failed (page $page). Hold the tag still and try again.',
      );
    }
    // Android may return the 4-bit ACK as 0x0A or an empty reply.
    if (res.isNotEmpty && (res[0] & 0x0F) != _ack) {
      throw TagWriteException(
        'The tag refused the write (page $page). It may be locked.',
      );
    }
  }

  Future<Uint8List> _cmd(List<int> command, String what) async {
    try {
      final res = await _t.transceive(Uint8List.fromList(command));
      if (res.length < 4) throw TagWriteException('Could not $what.');
      return res;
    } on TagWriteException {
      rethrow;
    } catch (_) {
      throw TagWriteException(
        'Could not $what. Hold the tag still and try again.',
      );
    }
  }
}

/// NDEF message TLV (type 0x03) + terminator, padded to whole 4-byte pages.
Uint8List ndefTlv(Uint8List message) {
  final b = BytesBuilder()..addByte(0x03);
  if (message.length < 0xFF) {
    b.addByte(message.length);
  } else {
    b
      ..addByte(0xFF)
      ..addByte(message.length >> 8)
      ..addByte(message.length & 0xFF);
  }
  b
    ..add(message)
    ..addByte(0xFE);
  while (b.length % 4 != 0) {
    b.addByte(0x00);
  }
  return b.toBytes();
}
