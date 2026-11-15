import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Desktop integration: native dialogs, default browser / file opener, clipboard.
/// Dialogs and clipboard access are asynchronous (they return Futures); paths are plain strings.
class Platform {
  Platform._();

  static final bool isMac = io.Platform.isMacOS;
  static final bool isWindows = io.Platform.isWindows;
  static final bool isLinux = io.Platform.isLinux;

  static Future<String?> pickDirectory(String title) async {
    try {
      return await FilePicker.getDirectoryPath(dialogTitle: title);
    } catch (_) {
      return null;
    }
  }

  static Future<String?> pickFile(String title) async {
    try {
      final f = await FilePicker.pickFile(dialogTitle: title);
      return f?.path;
    } catch (_) {
      return null;
    }
  }

  static Future<String?> saveFile(String title, String name) async {
    try {
      final uri = await FilePicker.saveFile(
        fileName: name,
        bytes: Uint8List(0),
        dialogTitle: title,
      );
      if (uri == null) return null;
      return uri.scheme == 'file' ? uri.toFilePath() : uri.toString();
    } catch (_) {
      return null;
    }
  }

  /// Opens a web address in the default browser.
  static Future<void> openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  static Future<void> _open(String path) async {
    if (io.Platform.isMacOS) {
      await io.Process.run('open', [path]);
    } else if (io.Platform.isWindows) {
      await io.Process.run('explorer', [path]);
    } else {
      await io.Process.run('xdg-open', [path]);
    }
  }

  /// Opens the folder containing [path] (or [path] itself when it is a directory) in the file manager.
  static Future<void> reveal(String path) async {
    try {
      await _open(
        io.FileSystemEntity.isDirectorySync(path) ? path : p.dirname(path),
      );
    } catch (_) {}
  }

  static Future<void> openBytes(
    Uint8List bytes,
    String ext, {
    bool browser = false,
  }) async {
    try {
      final f = io.File(
        p.join(
          io.Directory.systemTemp.path,
          'openrest-${DateTime.now().microsecondsSinceEpoch}$ext',
        ),
      );
      await f.writeAsBytes(bytes);
      if (browser) {
        await launchUrl(Uri.file(f.path), mode: LaunchMode.externalApplication);
      } else {
        await _open(f.path);
      }
    } catch (_) {}
  }

  static Future<void> copy(String text) async {
    try {
      await Clipboard.setData(ClipboardData(text: text));
    } catch (_) {}
  }

  static Future<String> paste() async {
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text ?? '';
    } catch (_) {
      return '';
    }
  }
}
