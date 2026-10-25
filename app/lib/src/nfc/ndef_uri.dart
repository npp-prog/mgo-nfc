import 'dart:convert';
import 'dart:typed_data';

import 'package:nfc_manager/ndef_record.dart';

/// NFC Forum URI Record Type Definition: the first payload byte abbreviates a
/// common prefix. Index = code.
const _uriPrefixes = [
  '',
  'http://www.',
  'https://www.',
  'http://',
  'https://',
  'tel:',
  'mailto:',
  'ftp://anonymous:anonymous@',
  'ftp://ftp.',
  'ftps://',
  'sftp://',
  'smb://',
  'nfs://',
  'ftp://',
  'dav://',
  'news:',
  'telnet://',
  'imap:',
  'rtsp://',
  'urn:',
  'pop:',
  'sip:',
  'sips:',
  'tftp:',
  'btspp://',
  'btl2cap://',
  'btgoep://',
  'tcpobex://',
  'irdaobex://',
  'file://',
  'urn:epc:id:',
  'urn:epc:tag:',
  'urn:epc:pat:',
  'urn:epc:raw:',
  'urn:epc:',
  'urn:nfc:',
];

final _typeU = Uint8List.fromList([0x55]); // "U"

/// Returns the URI in [record], or null if it is not a URI record.
String? decodeUriRecord(NdefRecord record) {
  try {
    if (record.typeNameFormat == TypeNameFormat.wellKnown &&
        record.type.length == 1 &&
        record.type[0] == 0x55) {
      final payload = record.payload;
      if (payload.isEmpty || payload[0] >= _uriPrefixes.length) return null;
      return _uriPrefixes[payload[0]] + utf8.decode(payload.sublist(1));
    }
    // Absolute-URI records carry the URI in the type field.
    if (record.typeNameFormat == TypeNameFormat.absoluteUri &&
        record.type.isNotEmpty) {
      return utf8.decode(record.type);
    }
  } on FormatException {
    return null;
  }
  return null;
}

/// First URI found in [message], or null.
String? firstUri(NdefMessage? message) {
  for (final r in message?.records ?? const <NdefRecord>[]) {
    final uri = decodeUriRecord(r);
    if (uri != null) return uri;
  }
  return null;
}

/// Builds a compact URI record, using the longest matching prefix code.
NdefRecord encodeUriRecord(String uri) {
  var code = 0;
  for (var i = 1; i < _uriPrefixes.length; i++) {
    if (uri.startsWith(_uriPrefixes[i]) &&
        _uriPrefixes[i].length > _uriPrefixes[code].length) {
      code = i;
    }
  }
  final rest = utf8.encode(uri.substring(_uriPrefixes[code].length));
  return NdefRecord(
    typeNameFormat: TypeNameFormat.wellKnown,
    type: _typeU,
    identifier: Uint8List(0),
    payload: Uint8List.fromList([code, ...rest]),
  );
}

/// Hex UID as the backend stores it: uppercase, no separators.
String formatTagUid(List<int> bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join().toUpperCase();
