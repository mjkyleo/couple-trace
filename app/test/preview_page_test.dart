import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_app/services/cache_service.dart';
import 'package:trace_app/ui/pages/preview_page.dart';
import 'package:trace_app/ui/providers.dart';

/// 只提供签名 URL，不碰网络与本地库
class _FakeCache implements CacheService {
  _FakeCache({this.url, this.error});

  final String? url;
  final Object? error;

  @override
  Future<String> signedUrl(String objectKey) async {
    if (error != null) throw error!;
    return url!;
  }

  @override
  Future<bool> exists(String objectKey) async => false;

  @override
  Future<String> resolve(String objectKey) async => throw UnimplementedError();

  @override
  Future<void> clearCache() async {}
}

Widget _wrap(CacheService cache, String mediaType) => ProviderScope(
      overrides: [cacheServiceProvider.overrideWithValue(cache)],
      child: MaterialApp(
        home: PreviewPage(objectKey: 'c1/clip.mp4', mediaType: mediaType),
      ),
    );

void main() {
  testWidgets('签名 URL 申请失败时给出错误文案', (tester) async {
    await tester.pumpWidget(_wrap(_FakeCache(error: Exception('403')), 'image'));
    await tester.pump();
    expect(find.textContaining('加载失败'), findsOneWidget);
  });

  testWidgets('视频初始化失败时回退为提示 + 重试，不把异常抛到上层', (tester) async {
    // flutter test 里没有 video_player 的平台实现，initialize() 必然失败，
    // 正好用来验证降级分支。
    await tester.pumpWidget(
      _wrap(_FakeCache(url: 'https://example.invalid/clip.mp4'), 'video'),
    );
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(tester.takeException(), isNull);
    expect(find.text('视频加载失败'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // 释放失败的 controller 走的是 2s 超时兜底，把定时器跑完再结束测试
    await tester.pump(const Duration(seconds: 3));
  });
}
