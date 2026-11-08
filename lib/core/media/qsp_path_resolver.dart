import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Resolves game-relative media paths against one or more game folders.
///
/// Heavy games ship tens of thousands of files. Indexing all of them up front
/// costs seconds of CPU and tens of megabytes of memory even though almost
/// every path resolves directly, so the index is built lazily the first time a
/// direct lookup misses. Results are cached, which keeps the per-frame cost of
/// an already resolved image at a single map lookup.
class QspPathResolver {
  QspPathResolver(this.basePaths);

  final List<String> basePaths;
  final Map<String, String> _relMap = {};
  final Map<String, String> _basenameMap = {};

  /// Lower-cased cleaned path to resolved absolute path, or null for a miss.
  final Map<String, String?> _cache = {};

  bool _indexing = false;
  bool _indexed = false;
  bool _indexRequested = false;

  void _ensureIndex() {
    if (_indexed || _indexRequested) return;
    _indexRequested = true;
    unawaited(_buildIndex());
  }

  Future<void> _buildIndex() async {
    if (_indexing || _indexed) return;
    _indexing = true;
    try {
      final validPaths = basePaths
          .where((b) => b.isNotEmpty && Directory(b).existsSync())
          .toList();
      if (validPaths.isEmpty) {
        _indexed = true;
        return;
      }

      final result = await Isolate.run(() {
        final rels = <String, String>{};
        final bases = <String, String>{};

        for (final basePath in validPaths) {
          try {
            final dir = Directory(basePath);
            if (!dir.existsSync()) continue;
            for (final entity
                in dir.listSync(recursive: true, followLinks: false)) {
              if (entity is File) {
                final rel = p
                    .relative(entity.path, from: basePath)
                    .replaceAll('\\', '/')
                    .toLowerCase();
                rels[rel] = entity.path;

                final parts = rel.split('/');
                for (var i = 1; i < parts.length; i++) {
                  final sub = parts.sublist(i).join('/');
                  rels.putIfAbsent(sub, () => entity.path);
                }

                final base = p.basename(entity.path).toLowerCase();
                bases.putIfAbsent(base, () => entity.path);
              }
            }
          } catch (_) {}
        }
        return (rels: rels, bases: bases);
      });

      _relMap.addAll(result.rels);
      _basenameMap.addAll(result.bases);
      _indexed = true;
    } catch (e) {
      debugPrint('[QspPathResolver] Error during async indexing: $e');
    } finally {
      _indexing = false;
    }
  }

  /// Case-insensitive lookup inside the target directory only.
  ///
  /// This handles the common "game ships mixed-case names" case without paying
  /// for a recursive scan of the whole game.
  String? _resolveInParent(String clean) {
    for (final basePath in basePaths) {
      if (basePath.isEmpty) continue;
      final joined = p.join(basePath, clean.replaceAll('/', p.separator));
      final direct = File(joined);
      if (direct.existsSync()) return direct.path;

      final parent = Directory(p.dirname(joined));
      if (!parent.existsSync()) continue;
      final wanted = p.basename(joined).toLowerCase();
      try {
        for (final entity in parent.listSync(followLinks: false)) {
          if (entity is File &&
              p.basename(entity.path).toLowerCase() == wanted) {
            return entity.path;
          }
        }
      } catch (_) {}
    }
    return null;
  }

  String? resolve(String raw) {
    if (raw.trim().isEmpty) return null;
    var clean = raw.trim();
    if (clean.contains('?')) clean = clean.split('?').first;
    if (clean.contains('#')) clean = clean.split('#').first;
    if (clean.startsWith('file://')) {
      try {
        clean = Uri.parse(clean).toFilePath();
      } catch (_) {}
    }
    clean = clean.replaceAll('\\', '/');
    while (clean.startsWith('/') || clean.startsWith('./')) {
      if (clean.startsWith('./')) {
        clean = clean.substring(2);
      } else {
        clean = clean.substring(1);
      }
    }

    if (p.isAbsolute(clean)) {
      if (File(clean).existsSync()) return clean;
    }

    final cacheKey = clean.toLowerCase();
    if (_cache.containsKey(cacheKey)) {
      final cached = _cache[cacheKey];
      if (cached != null && File(cached).existsSync()) return cached;
      if (cached == null && _indexed) return null;
    }

    final direct = _resolveInParent(clean);
    if (direct != null) {
      _cache[cacheKey] = direct;
      return direct;
    }

    // Deep lookups need the full index. It is built on demand so games whose
    // paths all resolve directly never pay for it.
    _ensureIndex();

    final fromRel = _relMap[cacheKey];
    if (fromRel != null && File(fromRel).existsSync()) {
      _cache[cacheKey] = fromRel;
      return fromRel;
    }

    final baseKey = p.basename(clean).toLowerCase();
    final fromBase = _basenameMap[baseKey];
    if (fromBase != null && File(fromBase).existsSync()) {
      _cache[cacheKey] = fromBase;
      return fromBase;
    }

    if (_indexed) _cache[cacheKey] = null;
    return null;
  }
}
