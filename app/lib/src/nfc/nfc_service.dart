import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';

import 'ndef_uri.dart';
import 'ntag_programmer.dart';

enum NfcStatus { enabled, disabled, unsupported }

/// What the phone read from a tag.
class ScannedTag {
  const ScannedTag({required this.uid, this.url});

  /// Uppercase hex UID, e.g. 04A1B2C3D4E5F6.
  final String uid;

  /// First URI record on the tag, if any.
  final String? url;
}

/// Reads tags while a session is active. Abstract so screens can be tested
/// without NFC hardware.
abstract class NfcService {
  Future<NfcStatus> status();

  /// Starts listening; [onTag] is called for every tag that comes into range
  /// until [stop] is called. [onError] gets tags that could not be read.
  Future<void> start({
    required void Function(ScannedTag tag) onTag,
    required void Function(Object error) onError,
  });

  /// Starts a session for writing: [onTag] gets the UID and a raw command
  /// channel, and runs while the tag stays in range.
  Future<void> startWriter({
    required Future<void> Function(String uid, TagTransport transport) onTag,
    required void Function(Object error) onError,
  });

  Future<void> stop();
}

class NfcReadException implements Exception {
  const NfcReadException(this.message);
  final String message;
  @override
  String toString() => message;
}

class NfcManagerService implements NfcService {
  NfcManager get _nfc => NfcManager.instance;

  @override
  Future<NfcStatus> status() async {
    if (kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return NfcStatus.unsupported;
    }
    return switch (await _nfc.checkAvailability()) {
      NfcAvailability.enabled => NfcStatus.enabled,
      NfcAvailability.disabled => NfcStatus.disabled,
      NfcAvailability.unsupported => NfcStatus.unsupported,
    };
  }

  @override
  Future<void> start({
    required void Function(ScannedTag tag) onTag,
    required void Function(Object error) onError,
  }) => _nfc.startSession(
    pollingOptions: {NfcPollingOption.iso14443},
    alertMessageIos: 'Hold your phone near the attendance tag.',
    invalidateAfterFirstReadIos: true,
    onDiscovered: (tag) async {
      try {
        onTag(await readTag(tag));
      } catch (e) {
        onError(e);
      }
    },
  );

  @override
  Future<void> startWriter({
    required Future<void> Function(String uid, TagTransport transport) onTag,
    required void Function(Object error) onError,
  }) => _nfc.startSession(
    pollingOptions: {NfcPollingOption.iso14443},
    alertMessageIos: 'Hold the tag near the top of your phone.',
    onDiscovered: (tag) async {
      try {
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          final mifare = MiFareIos.from(tag);
          if (mifare == null) {
            throw const NfcReadException('Unsupported tag type.');
          }
          await onTag(formatTagUid(mifare.identifier), _IosTransport(mifare));
        } else {
          final android = NfcTagAndroid.from(tag);
          final nfcA = NfcAAndroid.from(tag);
          if (android == null || nfcA == null) {
            throw const NfcReadException(
              'Unsupported tag type. Use NTAG213/215/216 stickers.',
            );
          }
          await onTag(formatTagUid(android.id), _AndroidTransport(nfcA));
        }
      } catch (e) {
        onError(e);
      }
    },
  );

  @override
  Future<void> stop() async {
    try {
      await _nfc.stopSession();
    } catch (_) {
      // No session running.
    }
  }

  /// Extracts UID and URL from a discovered tag (NTAG21x on Android or iOS).
  static Future<ScannedTag> readTag(NfcTag tag) async {
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      final mifare = MiFareIos.from(tag);
      if (mifare == null) throw const NfcReadException('Unsupported tag type.');
      final ndef = NdefIos.from(tag);
      final message = ndef?.cachedNdefMessage ?? await ndef?.readNdef();
      return ScannedTag(
        uid: formatTagUid(mifare.identifier),
        url: firstUri(message),
      );
    }
    final android = NfcTagAndroid.from(tag);
    if (android == null || android.id.isEmpty) {
      throw const NfcReadException('Could not read the tag ID.');
    }
    final ndef = NdefAndroid.from(tag);
    final message = ndef?.cachedNdefMessage ?? await ndef?.getNdefMessage();
    return ScannedTag(uid: formatTagUid(android.id), url: firstUri(message));
  }
}

class _AndroidTransport implements TagTransport {
  _AndroidTransport(this._tag);
  final NfcAAndroid _tag;
  @override
  Future<Uint8List> transceive(Uint8List command) => _tag.transceive(command);
}

class _IosTransport implements TagTransport {
  _IosTransport(this._tag);
  final MiFareIos _tag;
  @override
  Future<Uint8List> transceive(Uint8List command) =>
      _tag.sendMiFareCommand(commandPacket: command);
}
