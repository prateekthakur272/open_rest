import 'dart:io' as io;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:open_rest/core/logging/log.dart';
import 'package:open_rest/utils/paths.dart';
import 'package:path/path.dart' as p;
import 'package:url_launcher/url_launcher.dart';

/// Desktop integration: native dialogs, default browser / file opener, clipboard.
/// Dialogs and clipboard access are asynchronous (they return Futures); paths are plain strings.
class Platform {
  Platform._();

  static final bool isMac = io.Platform.isMacOS;
  static final bool isWindows = io.Platform.isWindows;
  static final bool isLinux = io.Platform.isLinux;

  /// Call once at startup. The app isn't sandboxed and doesn't declare the macOS file-access entitlements,
  /// so the file picker would otherwise refuse to open any dialog.
  static Future<void> init() async {
    try {
      await FilePicker.skipEntitlementsChecks();
    } catch (e, st) {
      Log.warning('platform', 'Could not configure the file picker', e, st);
    }
  }

  static Future<String?> pickDirectory(String title) async {
    try {
      return await FilePicker.getDirectoryPath(dialogTitle: title);
    } catch (e, st) {
      Log.warning('platform', 'Folder dialog failed', e, st);
      return null;
    }
  }

  static Future<String?> pickFile(String title) async {
    try {
      final f = await FilePicker.pickFile(dialogTitle: title);
      return f?.path;
    } catch (e, st) {
      Log.warning('platform', 'File dialog failed', e, st);
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
    } catch (e, st) {
      Log.warning('platform', 'Save dialog failed', e, st);
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

  /// Label for the reveal action in the platform's file manager.
  static String get revealLabel => io.Platform.isMacOS
      ? 'Show in Finder'
      : (io.Platform.isWindows ? 'Show in Explorer' : 'Show in file manager');

  /// Shows [path] in the file manager: its parent folder opens with the item selected.
  static Future<void> reveal(String path) async {
    try {
      if (io.Platform.isMacOS) {
        await io.Process.run('open', ['-R', path]);
      } else if (io.Platform.isWindows) {
        await io.Process.run('explorer', ['/select,', path]);
      } else {
        await _open(p.dirname(path));
      }
    } catch (_) {}
  }

  static Future<void> openBytes(
    Uint8List bytes,
    String ext, {
    bool browser = false,
  }) async {
    try {
      final f = io.File(Paths.tempFile(ext));
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
