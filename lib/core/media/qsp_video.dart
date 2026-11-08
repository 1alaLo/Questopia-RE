import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class QspVideo extends StatefulWidget {
  const QspVideo({
    super.key,
    required this.path,
    this.autoplay = true,
    this.loop = true,
    this.muted = false,
    this.fit = BoxFit.contain,
    this.width,
    this.height,
    this.mixWithOthers = true,
  });

  final String path;
  final bool autoplay;
  final bool loop;
  final bool muted;
  final BoxFit fit;
  final double? width;
  final double? height;

  /// Keeps the shared audio session usable by the QSP sound engine.
  ///
  /// Video playback otherwise takes over the session and silences the MP3
  /// sounds the game starts around the same time.
  final bool mixWithOthers;

  @override
  State<QspVideo> createState() => _QspVideoState();
}

class _QspVideoState extends State<QspVideo> {
  late VideoPlayerController _controller;
  late Future<void> _initFuture;
  bool _isReady = false;

  VideoPlayerController _createController(String path) {
    final lower = path.toLowerCase();
    final isRemote =
        lower.startsWith('http://') || lower.startsWith('https://');
    final options = VideoPlayerOptions(mixWithOthers: widget.mixWithOthers);
    return isRemote
        ? VideoPlayerController.networkUrl(Uri.parse(path),
            videoPlayerOptions: options)
        : VideoPlayerController.file(File(path), videoPlayerOptions: options);
  }

  @override
  void initState() {
    super.initState();
    _controller = _createController(widget.path);
    _initFuture = _applyOptions();
  }

  Future<void> _applyOptions() async {
    await _controller.initialize();
    await _controller.setLooping(widget.loop);
    await _controller.setVolume(widget.muted ? 0 : 1);
    if (!mounted) return;
    setState(() => _isReady = true);
    if (widget.autoplay) {
      await _controller.play();
    }
  }

  @override
  void didUpdateWidget(covariant QspVideo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _swapSource(widget.path);
    }
  }

  Future<void> _swapSource(String path) async {
    final previous = _controller;
    final next = _createController(path);
    await previous.dispose();
    if (!mounted) {
      await next.dispose();
      return;
    }
    setState(() {
      _isReady = false;
    });
    _controller = next;
    _initFuture = _applyOptions();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _aspectRatio {
    final ratio = _controller.value.aspectRatio;
    if (ratio.isNaN || ratio <= 0) return 16 / 9;
    return ratio;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _initFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const SizedBox.shrink();
        }
        if (!_isReady || !_controller.value.isInitialized) {
          return const SizedBox.shrink();
        }
        Widget video = VideoPlayer(_controller);
        if (widget.fit != BoxFit.contain) {
          video = FittedBox(
            fit: widget.fit,
            child: SizedBox(
              width: _controller.value.size.width,
              height: _controller.value.size.height,
              child: video,
            ),
          );
        }
        if (widget.width != null && widget.height != null) {
          video = SizedBox(
            width: widget.width,
            height: widget.height,
            child: video,
          );
        } else if (widget.width != null) {
          video = SizedBox(
            width: widget.width,
            child: AspectRatio(aspectRatio: _aspectRatio, child: video),
          );
        } else if (widget.height != null) {
          video = SizedBox(
            height: widget.height,
            child: AspectRatio(aspectRatio: _aspectRatio, child: video),
          );
        } else {
          video = AspectRatio(aspectRatio: _aspectRatio, child: video);
        }
        return ExcludeSemantics(child: Center(child: video));
      },
    );
  }
}