import 'dart:io';
import 'package:flutter/material.dart';
import 'qsp_media_kind.dart';
import 'qsp_ogv_video.dart';
import 'qsp_path_resolver.dart';
import 'qsp_video.dart';

class QspMedia extends StatelessWidget {
  const QspMedia({
    super.key,
    required this.src,
    this.resolver,
    this.width,
    this.height,
    this.fit = BoxFit.contain,
    this.autoplay = true,
    this.loop = true,
    this.muted = false,
    this.allowedRoots = const [],
  });

  final String src;
  final QspPathResolver? resolver;
  final double? width;
  final double? height;
  final BoxFit fit;
  final bool autoplay;
  final bool loop;
  final bool muted;

  /// Game folders the loopback OGV media server may read from.
  final List<String> allowedRoots;

  /// The platform decoder has no Theora support, so Ogg video must fall back
  /// to the bundled WebAssembly decoder instead.
  static bool _needsWebAssemblyDecoder(String source) {
    final lower = source.toLowerCase();
    final withoutQuery = lower.split('?')[0].split('#')[0];
    final isOgg = withoutQuery.endsWith('.ogv') || withoutQuery.endsWith('.ogg');
    if (isOgg) {
      debugPrint('[QspMedia] routing Ogg video to the WebAssembly decoder: $source');
    }
    return isOgg;
  }

  @override
  Widget build(BuildContext context) {
    if (src.isEmpty) return _broken(context);

    final isRemote =
        src.toLowerCase().startsWith('http://') ||
        src.toLowerCase().startsWith('https://');

    if (isRemote) {
      final kind = detectMediaKind(src);
      Widget child;
      if (kind == QspMediaKind.video) {
        if (_needsWebAssemblyDecoder(src)) {
          child = QspOgvVideo(
            key: ValueKey('ogv:$src'),
            path: src,
            autoplay: autoplay,
            loop: loop,
            muted: muted,
            width: width,
            height: height,
            allowedRoots: allowedRoots,
          );
        } else {
          child = QspVideo(
            key: ValueKey(src),
            path: src,
            autoplay: autoplay,
            loop: loop,
            muted: muted,
            fit: fit,
            width: width,
            height: height,
            mixWithOthers: true,
          );
        }
      } else {
        child = Image.network(
          src,
          fit: fit,
          errorBuilder: (_, __, ___) => _broken(context),
        );
      }
      final result = (width == null && height == null)
          ? child
          : SizedBox(width: width, height: height, child: child);
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: result,
      );
    }

    final path = resolver != null ? resolver!.resolve(src) : src;
    if (path == null || (resolver == null && !File(path).existsSync())) {
      return _broken(context);
    }

    final Widget child;
    switch (detectMediaKind(path)) {
      case QspMediaKind.image:
        child = Image.file(
          File(path),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _broken(context),
        );
        break;
      case QspMediaKind.video:
        if (_needsWebAssemblyDecoder(path)) {
          child = QspOgvVideo(
            key: ValueKey('ogv:$path'),
            path: path,
            autoplay: autoplay,
            loop: loop,
            muted: muted,
            width: width,
            height: height,
            allowedRoots: allowedRoots,
          );
        } else {
          child = QspVideo(
            key: ValueKey(path),
            path: path,
            autoplay: autoplay,
            loop: loop,
            muted: muted,
            fit: fit,
            width: width,
            height: height,
            mixWithOthers: true,
          );
        }
        break;
      case QspMediaKind.unknown:
        child = Image.file(
          File(path),
          fit: fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _broken(context),
        );
        break;
    }

    final result = (width == null && height == null)
        ? child
        : SizedBox(width: width, height: height, child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: result,
    );
  }

  Widget _broken(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: width ?? 48,
      height: height ?? 48,
      decoration: BoxDecoration(
        color: colors.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        Icons.broken_image_outlined,
        color: colors.onSurfaceVariant,
        size: 24,
      ),
    );
  }
}
