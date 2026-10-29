import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_app/core/api_client.dart';
import 'package:trace_app/core/token_store.dart';
import 'package:trace_app/models/models.dart';
import 'package:trace_app/services/couple_service.dart';
import 'package:trace_app/ui/app.dart';
import 'package:trace_app/ui/providers.dart';

/// 不发起网络请求的 CoupleService：可指定返回哪种绑定状态
class _StubCoupleService extends CoupleService {
  _StubCoupleService(this._result)
      : super(ApiClient(
          dio: Dio(),
          tokens: InMemoryTokenStore(),
        ));

  final Couple? _result;

  @override
  Future<Couple?> myCouple() async => _result;
}

Couple _couple({String? userB}) => Couple(
      id: 'c1',
      userA: 'user-001',
      userB: userB,
      inviteCode: 'A7K2Q9X4',
    );

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

  testWidgets('已有令牌但未创建空间时显示绑定引导', (tester) async {
    final tokens = InMemoryTokenStore();
    await tokens.write(makeJwtForTest('user-001'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          coupleServiceProvider.overrideWithValue(_StubCoupleService(null)),
        ],
        child: const TraceApp(),
      ),
    );
    await tester.pump();
    expect(find.text('同迹'), findsOneWidget);
    expect(find.text('去绑定'), findsOneWidget);
    expect(find.text('登录'), findsNothing);
  });

  testWidgets('空间已建但对方未加入：停在邀请码页，不进时光轴', (tester) async {
    final tokens = InMemoryTokenStore();
    await tokens.write(makeJwtForTest('user-001'));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          tokenStoreProvider.overrideWithValue(tokens),
          coupleServiceProvider
              .overrideWithValue(_StubCoupleService(_couple())),
        ],
        child: const TraceApp(),
      ),
    );
    await tester.pump();
    expect(find.text('空间已建好，等 TA 进来'), findsOneWidget);
    // 邀请码原样展示给发起方，让对方输入
    expect(find.text('A7K2Q9X4'), findsOneWidget);
    // 没配对成功就不该出现发布入口
    expect(find.byIcon(Icons.add), findsNothing);
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
