import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';

/// 媒体预览页：通过签名 URL 按需加载（图片先取签名再加载；
/// 视频可在真机接入 video_player 播放本地缓存文件）。
class PreviewPage extends ConsumerWidget {
  const PreviewPage({super.key, required this.objectKey, this.mediaType = 'image'});

  final String objectKey;
  final String mediaType;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Text(objectKey.split('/').last),
      ),
      body: Center(
        child: FutureBuilder<String>(
          future: ref
              .read(storageServiceProvider)
              .getDownloadSign(objectKey),
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
            if (mediaType == 'video') {
              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.play_circle_outline,
                      size: 72, color: Colors.white70),
                  const SizedBox(height: 12),
                  const Text('视频播放（真机接入 video_player）',
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 8),
                  SelectableText(url, style: const TextStyle(fontSize: 10, color: Colors.white38)),
                ],
              );
            }
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
