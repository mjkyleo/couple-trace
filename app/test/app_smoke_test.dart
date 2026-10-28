import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_app/core/api_client.dart';
import 'package:trace_app/core/token_store.dart';
import 'package:trace_app/models/models.dart';
import 'package:trace_app/services/couple_service.dart';
import 'package:trace_app/ui/app.dart';
import 'package:trace_app/ui/providers.dart';

/// 不发起网络请求的 CoupleService：模拟「未绑定」
class _StubCoupleService extends CoupleService {
  _StubCoupleService()
      : super(ApiClient(
          dio: Dio(),
          tokens: InMemoryTokenStore(),
        ));

  @override
  Future<Couple?> myCouple() async => null;
}

void main() {
  testWidgets('未登录时渲染登录页', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
        ],
        child: const TraceApp(),
      ),
    );
    expect(find.text('Trace · 同迹'), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('注册新账号'), findsOneWidget);
  });

  testWidgets('已有令牌时渲染时光轴页骨架（未绑定显示引导）', (tester) async {
    final tokens = InMemoryTokenStore();
    await tokens.write(makeJwtForTest('user-001'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          coupleServiceProvider.overrideWithValue(_StubCoupleService()),
        ],
        child: const TraceApp(),
      ),
    );
    await tester.pump();
    // 时光轴 AppBar 同步渲染；未绑定时显示绑定引导
    expect(find.text('时光轴'), findsOneWidget);
    expect(find.text('去绑定'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
  });
}

/// 生成 JWT 样式令牌（仅测试路由判定用）
String makeJwtForTest(String sub) {
  String enc(String s) =>
      base64UrlEncode(utf8.encode(s)).replaceAll('=', '');
  return '${enc('{"alg":"HS256","typ":"JWT"}')}.'
      '${enc('{"sub":"$sub"}')}.'
      'test-signature';
}
