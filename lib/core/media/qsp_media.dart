import 'dart:io';
import 'package:flutter/material.dart';
import 'qsp_media_kind.dart';
import 'qsp_ogv_video.dart';
import 'qsp_path_resolver.dart';
import 'qsp_video.dart';

/// Renders one image or video referenced by the game markup.
///
/// A stateful widget rather than a stateless one on purpose: the resolver
/// builds its file index in the background, so a path that misses on the very
/// first frame has to be retried once indexing finishes. Otherwise the broken
/// placeholder would be cached by [QspHtmlView] and the picture would only
/// appear after the description changed.
class QspMedia extends StatefulWidget {
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
      debugPrint(
          '[QspMedia] routing Ogg video to the WebAssembly decoder: $source');
    }
    return isOgg;
  }

  @override
  State<QspMedia> createState() => _QspMediaState();
}

class _QspMediaState extends State<QspMedia> {
  /// Absolute path the widget finally renders, or null while unresolved.
  String? _path;
  bool _waitingForIndex = false;

  bool get _isRemote =>
      widget.src.toLowerCase().startsWith('http://') ||
      widget.src.toLowerCase().startsWith('https://');

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant QspMedia oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.src != widget.src ||
        !identical(oldWidget.resolver, widget.resolver)) {
      _resolve();
    }
  }

  void _resolve() {
    final src = widget.src;
    if (src.isEmpty || _isRemote) {
      _path = src.isEmpty ? null : src;
      _waitingForIndex = false;
      return;
    }

    final resolver = widget.resolver;
    if (resolver == null) {
      _path = src;
      _waitingForIndex = false;
      return;
    }

    final resolved = resolver.resolve(src);
    _path = resolved;
    _waitingForIndex = resolved == null;
    if (resolved != null) return;

    // The path may simply be unknown until the background index is ready.
    resolver.ensureIndexed().then((_) {
      if (!mounted) return;
      setState(() {
        _path = resolver.resolve(src);
        _waitingForIndex = false;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.src.isEmpty) return _broken(context);

    if (_isRemote) return _buildRemote(context);

    final path = _path;
    if (path == null) {
      // While indexing is in flight keep the layout stable but unobtrusive.
      if (_waitingForIndex) return const SizedBox(width: 1, height: 1);
      return _broken(context);
    }
    if (widget.resolver == null && !File(path).existsSync()) {
      return _broken(context);
    }

    final Widget child;
    switch (detectMediaKind(path)) {
      case QspMediaKind.image:
        child = Image.file(
          File(path),
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _broken(context),
        );
        break;
      case QspMediaKind.video:
        if (QspMedia._needsWebAssemblyDecoder(path)) {
          child = QspOgvVideo(
            key: ValueKey('ogv:$path'),
            path: path,
            autoplay: widget.autoplay,
            loop: widget.loop,
            muted: widget.muted,
            width: widget.width,
            height: widget.height,
            allowedRoots: widget.allowedRoots,
          );
        } else {
          child = QspVideo(
            key: ValueKey(path),
            path: path,
            autoplay: widget.autoplay,
            loop: widget.loop,
            muted: widget.muted,
            fit: widget.fit,
            width: widget.width,
            height: widget.height,
            mixWithOthers: true,
          );
        }
        break;
      case QspMediaKind.unknown:
        child = Image.file(
          File(path),
          fit: widget.fit,
          gaplessPlayback: true,
          errorBuilder: (_, __, ___) => _broken(context),
        );
        break;
    }

    final result = (widget.width == null && widget.height == null)
        ? child
        : SizedBox(
            width: widget.width, height: widget.height, child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: result,
    );
  }

  Widget _buildRemote(BuildContext context) {
    final src = widget.src;
    final kind = detectMediaKind(src);
    Widget child;
    if (kind == QspMediaKind.video) {
      if (QspMedia._needsWebAssemblyDecoder(src)) {
        child = QspOgvVideo(
          key: ValueKey('ogv:$src'),
          path: src,
          autoplay: widget.autoplay,
          loop: widget.loop,
          muted: widget.muted,
          width: widget.width,
          height: widget.height,
          allowedRoots: widget.allowedRoots,
        );
      } else {
        child = QspVideo(
          key: ValueKey(src),
          path: src,
          autoplay: widget.autoplay,
          loop: widget.loop,
          muted: widget.muted,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
          mixWithOthers: true,
        );
      }
    } else {
      child = Image.network(
        src,
        fit: widget.fit,
        errorBuilder: (_, __, ___) => _broken(context),
      );
    }
    final result = (widget.width == null && widget.height == null)
        ? child
        : SizedBox(
            width: widget.width, height: widget.height, child: child);
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: result,
    );
  }

  Widget _broken(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Container(
      width: widget.width ?? 48,
      height: widget.height ?? 48,
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
