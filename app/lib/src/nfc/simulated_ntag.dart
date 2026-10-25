import 'dart:typed_data';

import 'ntag_programmer.dart';

/// In-memory NTAG21x used by tests and by test (emulator) mode, where there is
/// no NFC hardware. Follows the datasheet closely enough to exercise
/// [NtagProgrammer]: GET_VERSION, READ (16 bytes), WRITE (ACK/NAK),
/// PWD_AUTH, write protection from AUTH0, PWD/PACK reading as zeros, OTP
/// capability container, and halting after a failed authentication.
class SimulatedNtag implements TagTransport {
  SimulatedNtag({
    this.type = NtagType.ntag215,
    bool formatted = true,
    this.failAfterWrites,
  }) : _pages = List.generate(type.cfgPage + 4, (_) => Uint8List(4)) {
    _pages[type.cfgPage] = Uint8List.fromList([
      0x04,
      0x00,
      0x00,
      0xFF,
    ]); // AUTH0 = FF: unprotected
    _pages[type.cfgPage + 2] = Uint8List.fromList([0xFF, 0xFF, 0xFF, 0xFF]);
    if (formatted) {
      _pages[3] = Uint8List.fromList([0xE1, 0x10, type.ccSize, 0x00]);
    }
  }

  final NtagType type;
  final List<Uint8List> _pages;
  bool _authenticated = false;
  bool _halted = false;
  int writes = 0;

  /// Simulates pulling the tag away after this many writes.
  final int? failAfterWrites;

  int get auth0 => _pages[type.cfgPage][3];
  bool get protected => auth0 <= type.cfgPage + 3;
  Uint8List page(int p) => _pages[p];

  /// New field session: authentication is lost, as on a real tag.
  void reconnect() {
    _authenticated = false;
    _halted = false;
  }

  @override
  Future<Uint8List> transceive(Uint8List c) async {
    if (_halted) throw StateError('tag halted');
    switch (c[0]) {
      case 0x60:
        return Uint8List.fromList([
          0x00,
          0x04,
          0x04,
          0x02,
          0x01,
          0x00,
          _storageByte,
          0x03,
        ]);
      case 0x30:
        final out = BytesBuilder();
        for (var p = c[1]; p < c[1] + 4; p++) {
          final hidden =
              p == type.cfgPage + 2 ||
              p == type.cfgPage + 3; // PWD, PACK read as 0
          out.add(p < _pages.length && !hidden ? _pages[p] : Uint8List(4));
        }
        return out.toBytes();
      case 0xA2:
        final p = c[1];
        if (failAfterWrites != null && writes >= failAfterWrites!) {
          throw StateError('tag lost');
        }
        if (p < 3 ||
            p >= _pages.length ||
            (protected && p >= auth0 && !_authenticated)) {
          _halted = true;
          throw StateError('NAK');
        }
        final data = c.sublist(2, 6);
        if (p == 3) {
          for (var i = 0; i < 4; i++) {
            _pages[3][i] |= data[i]; // OTP
          }
        } else {
          _pages[p] = Uint8List.fromList(data);
        }
        writes++;
        return Uint8List.fromList([0x0A]);
      case 0x1B:
        final pwd = _pages[type.cfgPage + 2];
        final ok = List.generate(4, (i) => c[1 + i] == pwd[i]).every((x) => x);
        if (!ok) {
          _halted = true;
          throw StateError('NAK');
        }
        _authenticated = true;
        return Uint8List.fromList(_pages[type.cfgPage + 3].sublist(0, 2));
      default:
        throw StateError('unknown command ${c[0]}');
    }
  }

  int get _storageByte => switch (type) {
    NtagType.ntag213 => 0x0F,
    NtagType.ntag216 => 0x13,
    _ => 0x11,
  };
}
