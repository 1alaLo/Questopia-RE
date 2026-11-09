import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Mirrors a filtered subset of the app's debug output into a plain text file.
///
/// The build is sideloaded from a Windows machine with no attached debugger, so
/// when something misbehaves there is otherwise no way to see what the engine
/// did. The file lives under the app's Documents directory, which is exposed
/// through the Files app (`On My iPad/Questopia/logs/app.log`), so a bug report
/// only needs a copy of that file.
final class DebugLog {
  DebugLog._();

  /// Only lines with these markers are kept. Everything else is dropped so the
  /// log stays small and readable.
  static const List<String> _markers = <String>[
    '[GameAudio]',
    '[QuestopiaAudio]',
    '[GameEngineNotifier]',
    '[QspPathResolver]',
    '[QspMedia]',
    '[QSP Engine Debug]',
    '[QSP Engine System]',
  ];

  /// Hard cap for the on-disk file.
  static const int maxBytes = 256 * 1024;

  static final List<String> _pending = <String>[];
  static IOSink? _sink;
  static Timer? _flushTimer;
  static bool _installed = false;

  static bool get isInstalled => _installed;

  /// Installs the mirror. Safe to call more than once.
  static void install() {
    if (_installed) return;
    _installed = true;

    final original = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      original(message, wrapWidth: wrapWidth);
      if (message == null || message.isEmpty) return;
      if (!_markers.any(message.contains)) return;
      _pending.add(message);
      _flushTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
        unawaited(_flush());
      });
    };
  }

  /// Appends one line regardless of the marker filter.
  static void log(String message) {
    if (!_installed) return;
    _pending.add(message);
    _flushTimer ??= Timer.periodic(const Duration(seconds: 2), (_) {
      unawaited(_flush());
    });
  }

  static Future<File?> logFile() async {
    try {
      final docs = await getApplicationDocumentsDirectory();
      final dir = Directory(p.join(docs.path, 'Questopia', 'logs'));
      if (!await dir.exists()) {
        await dir.create(recursive: true);
      }
      return File(p.join(dir.path, 'app.log'));
    } catch (_) {
      return null;
    }
  }

  static Future<void> _flush() async {
    if (_pending.isEmpty) return;
    final batch = _pending.join('\n');
    _pending.clear();
    try {
      final file = await logFile();
      if (file == null) return;
      final sink = _sink ??= file.openWrite(mode: FileMode.append);
      final stamp = DateTime.now().toIso8601String();
      sink.writeln('--- $stamp');
      sink.writeln(batch);
      await sink.flush();
      if (await file.length() > maxBytes) {
        await _trim(file);
      }
    } catch (_) {
      // Logging must never break the app.
    }
  }

  static Future<void> _trim(File file) async {
    try {
      if (await file.length() <= maxBytes) return;
      final content = await file.readAsString();
      final keepFrom = content.length - maxBytes;
      final cut = content.indexOf('--- ', keepFrom);
      await file.writeAsString(
        cut >= 0 ? content.substring(cut) : content.substring(keepFrom),
        flush: true,
      );
    } catch (_) {
      // Best effort.
    }
  }
}
