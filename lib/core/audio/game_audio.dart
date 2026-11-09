import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

abstract interface class AudioBackend {
  Future<void> play(String absolutePath, double volume);
  Future<void> pause(String absolutePath);
  Future<void> resume(String absolutePath);
  Future<void> stop(String absolutePath);
  Future<void> setVolume(String absolutePath, double volume);
  Future<void> dispose(String absolutePath);
}

final class AudioPlayersBackend implements AudioBackend {
  final Map<String, AudioPlayer> _players = {};

  AudioPlayer _playerFor(String absolutePath) {
    return _players.putIfAbsent(absolutePath, AudioPlayer.new);
  }

  @override
  Future<void> play(String absolutePath, double volume) async {
    try {
      final player = _playerFor(absolutePath);
      await player.setVolume(volume);
      await player.play(DeviceFileSource(absolutePath));
    } catch (e) {
      debugPrint(
          '[GameAudio] audioplayers failed to play "$absolutePath": $e');
    }
  }

  @override
  Future<void> pause(String absolutePath) async {
    try {
      await _players[absolutePath]?.pause();
    } catch (e) {
      debugPrint('[GameAudio] audioplayers pause failed: $e');
    }
  }

  @override
  Future<void> resume(String absolutePath) async {
    try {
      await _players[absolutePath]?.resume();
    } catch (e) {
      debugPrint('[GameAudio] audioplayers resume failed: $e');
    }
  }

  @override
  Future<void> stop(String absolutePath) async {
    try {
      await _players[absolutePath]?.stop();
    } catch (e) {
      debugPrint('[GameAudio] audioplayers stop failed: $e');
    }
  }

  @override
  Future<void> setVolume(String absolutePath, double volume) async {
    try {
      await _players[absolutePath]?.setVolume(volume);
    } catch (e) {
      debugPrint('[GameAudio] audioplayers volume failed: $e');
    }
  }

  @override
  Future<void> dispose(String absolutePath) async {
    final player = _players.remove(absolutePath);
    if (player != null) {
      try {
        await player.dispose();
      } catch (e) {
        debugPrint('[GameAudio] audioplayers dispose failed: $e');
      }
    }
  }
}

/// Plays QSP sounds through the small AVAudioPlayer bridge in `AppDelegate`.
///
/// The stock audioplayers implementation leaves the shared audio session
/// inactive until a sound finishes, which can leave a freshly started game
/// completely silent on iOS. The native bridge activates a `.playback` session
/// on the first sound and keeps MP3 playback independent of the ring/silent
/// switch. It falls back to audioplayers whenever the channel is missing or the
/// native player reports a failure.
final class NativeIosAudioBackend implements AudioBackend {
  static const MethodChannel _channel = MethodChannel('questopia/audio');

  AudioPlayersBackend? _fallback;
  bool _unavailable = false;
  bool _loggedStatus = false;

  AudioPlayersBackend get _fallbackBackend =>
      _fallback ??= AudioPlayersBackend();

  /// Returns null when the native side handled the call, otherwise a short
  /// reason. The reason is logged so it ends up in the on-device log file.
  Future<String?> _call(String method, Map<String, Object?> arguments) async {
    if (_unavailable) return 'channel unavailable';
    try {
      final result = await _channel.invokeMethod<Object?>(method, arguments);
      if (result is String) return result;
      return null;
    } on MissingPluginException {
      _unavailable = true;
      debugPrint(
          '[QuestopiaAudio] native channel missing, using audioplayers instead');
      return 'channel missing';
    } catch (e) {
      debugPrint('[QuestopiaAudio] "$method" threw: $e');
      return 'exception: $e';
    }
  }

  @override
  Future<void> play(String absolutePath, double volume) async {
    final failure =
        await _call('play', {'path': absolutePath, 'volume': volume});
    if (failure == null) {
      if (!_loggedStatus) {
        _loggedStatus = true;
        await _logStatus();
      }
      return;
    }
    debugPrint(
        '[QuestopiaAudio] native play failed ($failure) for "$absolutePath"');
    await _fallbackBackend.play(absolutePath, volume);
  }

  /// Writes the native session state into the log once, so a silent device
  /// still reports whether the audio session actually became active.
  Future<void> _logStatus() async {
    try {
      final status = await _channel.invokeMethod<Object?>('status');
      debugPrint('[QuestopiaAudio] session status: $status');
    } catch (e) {
      debugPrint('[QuestopiaAudio] status unavailable: $e');
    }
  }

  @override
  Future<void> pause(String absolutePath) async {
    final failure = await _call('pause', {'path': absolutePath});
    if (failure == null) return;
    await _fallbackBackend.pause(absolutePath);
  }

  @override
  Future<void> resume(String absolutePath) async {
    final failure = await _call('resume', {'path': absolutePath});
    if (failure == null) return;
    await _fallbackBackend.resume(absolutePath);
  }

  @override
  Future<void> stop(String absolutePath) async {
    final failure = await _call('stop', {'path': absolutePath});
    if (failure == null) return;
    await _fallbackBackend.stop(absolutePath);
  }

  @override
  Future<void> setVolume(String absolutePath, double volume) async {
    final failure =
        await _call('setVolume', {'path': absolutePath, 'volume': volume});
    if (failure == null) return;
    await _fallbackBackend.setVolume(absolutePath, volume);
  }

  @override
  Future<void> dispose(String absolutePath) async {
    final failure = await _call('dispose', {'path': absolutePath});
    if (failure == null) return;
    await _fallbackBackend.dispose(absolutePath);
  }
}

final class _SoundEntry {
  _SoundEntry({required this.path, required this.volume});

  final String path;
  int volume;
}

/// QSP game audio service mirroring the legacy `AudioPlayer` behavior.
///
/// Keeps one cached entry per sound path, resolves relative game paths
/// against the active game directory (case-insensitively), maps the QSP
/// 0-100 volume range onto the player 0.0-1.0 range, and honors the
/// `isSoundEnabled` preference. The engine callback bridge calls
/// [playFile] and [closeFile].
final class GameAudio {
  GameAudio({AudioBackend? backend})
      : _backend = backend ?? _defaultBackend();

  static AudioBackend _defaultBackend() {
    if (Platform.isIOS) return NativeIosAudioBackend();
    return AudioPlayersBackend();
  }

  final AudioBackend _backend;
  final Map<String, _SoundEntry> _sounds = {};

  String _gameDirectory = '';
  bool _soundEnabled = true;
  bool _paused = false;
  bool _loggedFirstPlay = false;

  void setGameDirectory(String directory) {
    _gameDirectory = directory;
    debugPrint('[GameAudio] game directory: "$directory"');
  }

  void setSoundEnabled(bool enabled) {
    _soundEnabled = enabled;
    debugPrint('[GameAudio] sound enabled: $enabled');
    if (!enabled) {
      pauseAll();
    }
  }

  /// Resolves [path] against the game directory, falling back to a
  /// case-insensitive lookup like the legacy `MediaUtil`.
  String? resolvePath(String path) {
    final trimmed = path.trim();
    if (trimmed.isEmpty) return null;
    final direct = File(trimmed);
    if (direct.isAbsolute && direct.existsSync()) return direct.path;
    if (_gameDirectory.isEmpty) {
      return direct.existsSync() ? direct.path : null;
    }
    final joined = p.join(_gameDirectory, trimmed);
    final parent = Directory(p.dirname(joined));
    if (parent.existsSync()) {
      final wanted = p.basename(joined).toLowerCase();
      try {
        for (final entity in parent.listSync(followLinks: false)) {
          if (entity is File &&
              p.basename(entity.path).toLowerCase() == wanted) {
            return entity.path;
          }
        }
      } catch (_) {
        return null;
      }
    }
    if (File(joined).existsSync()) return joined;
    return null;
  }

  static double volumeToGain(int volume) => (volume.clamp(0, 100)) / 100.0;

  Future<void> playFile(String path, int volume) async {
    final resolved = resolvePath(path);
    if (resolved == null) {
      debugPrint('[GameAudio] sound not found: "$path" '
          '(game directory: "$_gameDirectory")');
      return;
    }
    if (!_loggedFirstPlay) {
      _loggedFirstPlay = true;
      debugPrint('[GameAudio] first sound: "$resolved" at volume $volume');
    }
    final key = resolved.toLowerCase();
    final entry = _sounds.putIfAbsent(
      key,
      () => _SoundEntry(path: resolved, volume: volume),
    );
    entry.volume = volume;
    if (!_soundEnabled || _paused) return;
    await _backend.play(resolved, volumeToGain(volume));
  }

  Future<void> closeFile(String path) async {
    final resolved = resolvePath(path);
    final key = (resolved ?? path).toLowerCase();
    if (_sounds.remove(key) == null) return;
    if (resolved != null) {
      await _backend.stop(resolved);
      await _backend.dispose(resolved);
    }
  }

  Future<void> closeAllFiles() async {
    final entries = _sounds.values.toList();
    _sounds.clear();
    for (final entry in entries) {
      await _backend.stop(entry.path);
      await _backend.dispose(entry.path);
    }
  }

  Future<void> pauseAll() async {
    for (final entry in _sounds.values) {
      await _backend.pause(entry.path);
    }
  }

  Future<void> resumeAll() async {
    if (!_soundEnabled) return;
    for (final entry in _sounds.values) {
      await _backend.resume(entry.path);
    }
  }

  void setPaused(bool paused) {
    _paused = paused;
    if (paused) {
      pauseAll();
    } else {
      resumeAll();
    }
  }

  bool get hasActiveSounds => _sounds.isNotEmpty;
}
