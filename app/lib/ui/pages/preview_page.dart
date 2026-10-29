import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../providers.dart';

/// 媒体预览页：图片可缩放，视频用 video_player 内嵌播放。
/// 签名 URL 统一走 CacheService（内存缓存，过期会重新申请）。
class PreviewPage extends ConsumerWidget {
  const PreviewPage({
    super.key,
    required this.objectKey,
    this.mediaType = 'image',
  });

  final String objectKey;
  final String mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cache = ref.watch(cacheServiceProvider);
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(objectKey.split('/').last),
      ),
      body: Center(
        child: FutureBuilder<String>(
          future: cache.signedUrl(objectKey),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const CircularProgressIndicator(color: Colors.white);
            }
            if (snap.hasError) {
              return Text(
                '加载失败：${snap.error}',
                style: const TextStyle(color: Colors.white70),
              );
            }
            final url = snap.data!;
            if (mediaType == 'video') return _VideoView(url: url);
            return InteractiveViewer(
              child: Image.network(
                url,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Text(
                  '图片加载失败',
                  style: TextStyle(color: Colors.white70),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _VideoView extends StatefulWidget {
  const _VideoView({required this.url});

  final String url;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> with WidgetsBindingObserver {
  VideoPlayerController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init() async {
    final c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await c.initialize();
      if (!mounted) {
        await _safeDispose(c);
        return;
      }
      setState(() {
        _controller = c;
        _loading = false;
      });
    } catch (e) {
      // 初始化失败时 controller.dispose() 会等待那个永远不会完成的初始化 future，
      // 所以先切到降级 UI，再后台释放，不能 await。
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
      unawaited(_safeDispose(c));
    }
  }

  /// 初始化失败的 controller 释放可能抛错或挂起，这里兜底吞掉
  Future<void> _safeDispose(VideoPlayerController c) async {
    try {
      await c.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {
      // 播放器没起来时释放失败没有可恢复的动作
    }
  }

  void _retry() {
    setState(() {
      _loading = true;
      _error = null;
    });
    _init();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _controller?.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const CircularProgressIndicator(color: Colors.white);
    final c = _controller;
    if (c == null || _error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.videocam_off_outlined, size: 56, color: Colors.white70),
          const SizedBox(height: 12),
          const Text('视频加载失败', style: TextStyle(color: Colors.white70)),
          if (_error != null) ...[
            const SizedBox(height: 6),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _error!,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 10, color: Colors.white38),
              ),
            ),
          ],
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: _retry,
            style: OutlinedButton.styleFrom(foregroundColor: Colors.white70),
            child: const Text('重试'),
          ),
        ],
      );
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AspectRatio(
          aspectRatio: c.value.aspectRatio == 0 ? 16 / 9 : c.value.aspectRatio,
          child: VideoPlayer(c),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (context, value, _) => IconButton(
                  color: Colors.white,
                  tooltip: value.isPlaying ? '暂停' : '播放',
                  icon: Icon(
                    value.isPlaying
                        ? Icons.pause_circle_outline
                        : Icons.play_circle_outline,
                    size: 32,
                  ),
                  onPressed: () =>
                      value.isPlaying ? c.pause() : c.play(),
                ),
              ),
              Expanded(
                child: VideoProgressIndicator(
                  c,
                  allowScrubbing: true,
                  colors: const VideoProgressColors(
                    playedColor: Colors.white,
                    bufferedColor: Colors.white24,
                    backgroundColor: Colors.white12,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: c,
                builder: (context, value, _) => Text(
                  '${_fmt(value.position)} / ${_fmt(value.duration)}',
                  style: const TextStyle(fontSize: 11, color: Colors.white70),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}
