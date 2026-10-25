import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a generated file to the user (save to Drive, email, etc.).
abstract class FileSharer {
  Future<void> shareText({
    required String filename,
    required String content,
    required String mimeType,
  });
}

class ShareSheetFileSharer implements FileSharer {
  @override
  Future<void> shareText({
    required String filename,
    required String content,
    required String mimeType,
  }) async {
    // Temporary directory: the OS cleans it up; nothing lingers in app storage.
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$filename');
    await file.writeAsString(content, encoding: utf8, flush: true);
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(file.path, mimeType: mimeType)],
        subject: filename,
      ),
    );
  }
}
