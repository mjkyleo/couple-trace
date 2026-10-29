import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_app/core/api_client.dart';
import 'package:trace_app/core/token_store.dart';
import 'package:trace_app/db/app_database.dart';
import 'package:trace_app/models/models.dart';
import 'package:trace_app/services/cache_service.dart';
import 'package:trace_app/services/couple_service.dart';
import 'package:trace_app/services/moment_service.dart';
import 'package:trace_app/ui/pages/bind_page.dart';
import 'package:trace_app/ui/pages/login_page.dart';
import 'package:trace_app/ui/pages/moment_detail_page.dart';
import 'package:trace_app/ui/pages/preview_page.dart';
import 'package:trace_app/ui/pages/publish_page.dart';
import 'package:trace_app/ui/pages/settings_page.dart';
import 'package:trace_app/ui/pages/timeline_page.dart';
import 'package:trace_app/ui/providers.dart';
import 'package:trace_app/ui/theme.dart';

/// 界面快照工具：没有 Android SDK / VS C++ 也能看到真实渲染结果。
///
///   UI_SNAPSHOTS=1 flutter test --update-goldens test/ui_snapshots_test.dart
///
/// 产物落在 test/goldens/*.png（不入库）。默认 skip，不参与 CI 门禁：
/// 出图依赖本机字体，跨环境比对必然抖动。
final bool _enabled = Platform.environment['UI_SNAPSHOTS'] == '1';

/// 测试环境没有系统字体，中文会渲染成方块。这里挂本机 TTF + SDK 里的图标字体顶上。
Future<String> _loadCJKFont() async {
  const candidates = [
    r'C:\Windows\Fonts\simhei.ttf',
    r'C:\Windows\Fonts\Deng.ttf',
    '/usr/share/fonts/truetype/noto/NotoSansCJK-Regular.ttc',
  ];
  for (final path in candidates) {
    final f = File(path);
    if (!f.existsSync()) continue;
    final loader = FontLoader('SnapshotFont')
      ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    await loader.load();
    return 'SnapshotFont';
  }
  return '';
}

/// 图标字体在 Flutter SDK 缓存里，不挂上 Icons.xxx 全是方块。
Future<void> _loadIconFont() async {
  final dartBin = File(Platform.resolvedExecutable).parent.path;
  final roots = [
    '${Platform.environment['FLUTTER_ROOT'] ?? ''}/bin',
    '$dartBin/../../..', // <flutter>/bin/cache/dart-sdk/bin
  ];
  for (final root in roots) {
    final f = File('$root/cache/artifacts/material_fonts/materialicons-regular.otf');
    if (!f.existsSync()) continue;
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(f.readAsBytesSync().buffer.asByteData()));
    await loader.load();
    return;
  }
  stderr.writeln('未找到 MaterialIcons 字体，快照里的图标会是方块');
}

class _StubCoupleService extends CoupleService {
  _StubCoupleService(this._couple)
      : super(ApiClient(dio: _unusedDio(), tokens: InMemoryTokenStore()));

  final Couple? _couple;

  @override
  Future<Couple?> myCouple() async => _couple;
}

class _StubMomentService extends MomentService {
  _StubMomentService(this._moments)
      : super(ApiClient(dio: _unusedDio(), tokens: InMemoryTokenStore()));

  final List<Moment> _moments;

  @override
  Future<List<Moment>> listMoments(String coupleId,
      {int limit = 50, DateTime? before}) async {
    return _moments;
  }

  @override
  Future<List<MomentComment>> listComments(String momentId) async {
    return _moments.expand((m) => m.comments).toList();
  }

  @override
  Future<void> deleteMoment(String momentId) async {}

  @override
  Future<MomentComment> addComment(String momentId, String authorId, String body,
      {String? parentId}) async {
    throw UnimplementedError();
  }
}

class _FakeCache implements CacheService {
  @override
  Future<String> signedUrl(String objectKey) async =>
      'https://snapshot.invalid/$objectKey';

  @override
  Future<bool> exists(String objectKey) async => false;

  @override
  Future<String> resolve(String objectKey) async => throw UnimplementedError();

  @override
  Future<void> clearCache() async {}
}

Dio _unusedDio() => Dio();

String _jwt(String sub) {
  String enc(String s) => base64UrlEncode(utf8.encode(s)).replaceAll('=', '');
  return '${enc('{"alg":"HS256","typ":"JWT"}')}.${enc('{"sub":"$sub"}')}.sig';
}

const _me = 'user-001';
const _ta = 'user-002';
// 服务端返回的是 uuid，设置页会截断前 8 位展示
const _cid = '7d9f2c14-8a3b-4e5f-9c1a-2b3d4e5f6a7b';

Couple _couple() => Couple(
      id: _cid,
      userA: _me,
      userB: _ta,
      inviteCode: 'A7K2Q9X4',
      startedOn: DateTime(2024, 5, 20),
    );

List<Moment> _feed() {
  final now = DateTime(2026, 10, 29, 21, 12);
  return [
    Moment(
      id: 'm3',
      coupleId: _cid,
      publisherId: _me,
      content: '今天路过我们第一次吃饭的那家店，招牌换了，菜还是那个味。',
      locationText: '西湖·断桥',
      createdAt: now.subtract(const Duration(hours: 5)),
      updatedAt: now.subtract(const Duration(hours: 4, minutes: 30)),
      media: const [
        MomentMedia(id: 'f1', momentId: 'm3', objectKey: 'a/1.jpg', mediaType: 'image'),
        MomentMedia(id: 'f2', momentId: 'm3', objectKey: 'a/2.jpg', mediaType: 'image'),
        MomentMedia(id: 'f3', momentId: 'm3', objectKey: 'a/3.mp4', mediaType: 'video'),
      ],
      comments: [
        MomentComment(
          id: 'c1',
          momentId: 'm3',
          authorId: _ta,
          body: '我记得是门口那棵樟树旁边那家',
          createdAt: now.subtract(const Duration(hours: 4)),
        ),
        MomentComment(
          id: 'c2',
          momentId: 'm3',
          authorId: _me,
          body: '对，就是那家',
          parentId: 'c1',
          createdAt: now.subtract(const Duration(hours: 3, minutes: 50)),
        ),
      ],
    ),
    Moment(
      id: 'm2',
      coupleId: _cid,
      publisherId: _ta,
      content: '加班到十点半，冰箱里有汤，记得热一下再喝。',
      createdAt: now.subtract(const Duration(days: 1, hours: 2)),
      updatedAt: now.subtract(const Duration(days: 1, hours: 2)),
    ),
    Moment(
      id: 'm1',
      coupleId: _cid,
      publisherId: _me,
      content: '',
      createdAt: now.subtract(const Duration(days: 3)),
      updatedAt: now.subtract(const Duration(days: 3)),
      media: const [
        MomentMedia(id: 'f0', momentId: 'm1', objectKey: 'b/0.jpg', mediaType: 'image'),
      ],
    ),
  ];
}

Widget _screen(Widget child,
    {required InMemoryTokenStore tokens, Couple? couple, List<Moment>? moments}) {
  final api = ApiClient(dio: _unusedDio(), tokens: tokens);
  final db = AppDatabase(NativeDatabase.memory());
  addTearDown(db.close);
  return ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokens),
      apiClientProvider.overrideWithValue(api),
      dbProvider.overrideWithValue(db),
      cacheServiceProvider.overrideWithValue(_FakeCache()),
      coupleServiceProvider
          .overrideWithValue(_StubCoupleService(couple ?? _couple())),
      momentServiceProvider
          .overrideWithValue(_StubMomentService(moments ?? _feed())),
    ],
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme,
      home: child,
    ),
  );
}

late ThemeData _theme;

void main() {
  setUpAll(() async {
    await _loadIconFont();
    final family = await _loadCJKFont();
    final base = buildTraceTheme();
    _theme = family.isEmpty
        ? base
        : base.copyWith(textTheme: base.textTheme.apply(fontFamily: family));
  });

  Future<void> shot(WidgetTester tester, String name, Widget child,
      {Couple? couple, List<Moment>? moments}) async {
    tester.view.physicalSize = const Size(828, 1792);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    final tokens = InMemoryTokenStore();
    await tokens.write(_jwt(_me));
    await tester
        .pumpWidget(_screen(child, tokens: tokens, couple: couple, moments: moments));
    await tester.pump();
    await tester.pump();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/$name.png'),
    );
  }

  testWidgets('登录', (tester) => shot(tester, '01_login', const LoginPage()),
      skip: !_enabled);

  testWidgets('绑定', (tester) => shot(
      tester, '02_bind', const BindPage(), couple: null), skip: !_enabled);

  testWidgets('时光轴·等对方加入', (tester) => shot(
        tester,
        '03_gate_waiting',
        const TimelinePage(),
        couple: const Couple(
            id: _cid, userA: _me, inviteCode: 'A7K2Q9X4', userB: null),
      ), skip: !_enabled);

  testWidgets('时光轴·有内容', (tester) =>
      shot(tester, '04_timeline', const TimelinePage()), skip: !_enabled);

  testWidgets('时光轴·空态', (tester) =>
      shot(tester, '05_timeline_empty', const TimelinePage(), moments: const []),
      skip: !_enabled);

  testWidgets('详情与评论', (tester) => shot(
      tester, '06_detail', MomentDetailPage(moment: _feed().first),
      moments: _feed()), skip: !_enabled);

  testWidgets('发布', (tester) =>
      shot(tester, '07_publish', const PublishPage()), skip: !_enabled);

  testWidgets('编辑', (tester) => shot(
      tester, '08_publish_edit', PublishPage(editing: _feed().first)),
      skip: !_enabled);

  testWidgets('设置', (tester) =>
      shot(tester, '09_settings', const SettingsPage()), skip: !_enabled);

  testWidgets('图片预览', (tester) => shot(
      tester,
      '10_preview_image',
      const PreviewPage(objectKey: 'a/1.jpg'),
    ), skip: !_enabled);
}
