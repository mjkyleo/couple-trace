import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_app/core/api_client.dart';
import 'package:trace_app/core/token_store.dart';
import 'package:trace_app/services/auth_service.dart';
import 'package:trace_app/services/couple_service.dart';
import 'package:trace_app/services/moment_service.dart';
import 'package:trace_app/services/storage_service.dart';

import 'fakes.dart';

ApiClient makeApi(FakeDioAdapter adapter, TokenStore tokens) {
  final dio = Dio()..httpClientAdapter = adapter;
  return ApiClient(
    dio: dio,
    tokens: tokens,
    supabaseUrl: 'https://test.memfiredb.com',
    anonKey: 'test-anon',
  );
}

/// Dio 的 RequestOptions.data 可能是已编码字符串或原始 Map
Map<String, dynamic> decodeBody(RequestOptions options) {
  final data = options.data;
  if (data is String) {
    return jsonDecode(data) as Map<String, dynamic>;
  }
  if (data is Map) {
    return Map<String, dynamic>.from(data);
  }
  return const {};
}

void main() {
  group('ApiClient.currentUserId', () {
    test('从 JWT payload 解析 sub', () {
      final tokens = InMemoryTokenStore();
      final api = makeApi(FakeDioAdapter(), tokens);
      tokens.write(makeTestJwt('user-001'));
      expect(api.currentUserId, 'user-001');
    });

    test('无令牌时返回 null', () {
      final tokens = InMemoryTokenStore();
      final api = makeApi(FakeDioAdapter(), tokens);
      expect(api.currentUserId, isNull);
    });
  });

  group('ApiClient.signIn', () {
    test('成功时写入 token', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) => jsonResponse({
            'access_token': makeTestJwt('user-001'),
            'user': {'id': 'user-001', 'email': 'a@b.com'},
          });
      final tokens = InMemoryTokenStore();
      final api = makeApi(adapter, tokens);

      final data = await api.signIn('a@b.com', 'pw');
      expect(data['access_token'], isNotNull);
      expect(tokens.lastRead, isNotNull);
      expect(api.currentUserId, 'user-001');
    });
  });

  group('AuthService', () {
    test('signIn 返回 User', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) => jsonResponse({
            'access_token': makeTestJwt('user-001'),
            'user': {'id': 'user-001', 'email': 'a@b.com'},
          });
      final api = makeApi(adapter, InMemoryTokenStore());
      final user = await AuthService(api).signIn('a@b.com', 'pw');
      expect(user.id, 'user-001');
      expect(user.email, 'a@b.com');
    });

    test('signUp 缺少 user 时抛异常', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) => jsonResponse({'id': 'no-user'});
      final api = makeApi(adapter, InMemoryTokenStore());
      expect(
        () => AuthService(api).signUp('a@b.com', 'pw'),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('CoupleService', () {
    test('generateInviteCode 生成 8 位安全字符', () {
      final code = CoupleService.generateInviteCode();
      expect(code, hasLength(8));
      expect(RegExp(r'^[A-HJ-NP-Z2-9]{8}$').hasMatch(code), isTrue);
    });

    test('createCouple 写入 couples 表', () async {
      final adapter = FakeDioAdapter();
      final tokens = InMemoryTokenStore();
      tokens.write(makeTestJwt('user-001'));
      adapter.onRequest = (options) {
        expect(options.uri.path, endsWith('/rest/v1/couples'));
        // PostgREST 只有带上该头才会返回写入的行，缺了则为空 body
        expect(options.headers['Prefer'], 'return=representation');
        final body = decodeBody(options);
        expect(body['user_a'], 'user-001');
        expect(body['invite_code'], hasLength(8));
        return jsonResponse([
          {
            'id': 'c1',
            'user_a': 'user-001',
            'invite_code': body['invite_code'],
          }
        ]);
      };
      final couple =
          await CoupleService(makeApi(adapter, tokens)).createCouple();
      expect(couple.id, 'c1');
      expect(couple.inviteCode, hasLength(8));
      expect(couple.userA, 'user-001');
    });

    test('dbInsert 未返回行时抛异常，而不是把空 Map 推进 fromJson', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) => jsonResponse([]);
      final api = makeApi(adapter, InMemoryTokenStore());
      expect(
        () => api.dbInsert('moments', {'content': 'x'}),
        throwsA(isA<Exception>()),
      );
    });

    test('addMedia 解析 representation 数组响应', () async {
      final adapter = FakeDioAdapter();
      final tokens = InMemoryTokenStore();
      adapter.onRequest = (options) {
        expect(options.uri.path, endsWith('/rest/v1/moment_media'));
        expect(options.headers['Prefer'], 'return=representation');
        return jsonResponse([
          {
            'id': 'm1',
            'moment_id': 'moment-1',
            'object_key': 'c1/photo.jpg',
            'media_type': 'image',
            'sort': 0,
          }
        ]);
      };
      final media = await MomentService(makeApi(adapter, tokens))
          .addMedia('moment-1', 'c1/photo.jpg', 'image');
      expect(media.id, 'm1');
      expect(media.objectKey, 'c1/photo.jpg');
      expect(media.mediaType, 'image');
    });

    test('joinCouple 调用 join_couple RPC 并回查', () async {
      final adapter = FakeDioAdapter();
      final tokens = InMemoryTokenStore();
      tokens.write(makeTestJwt('user-002'));
      var rpcCalled = false;
      adapter.onRequest = (options) {
        if (options.uri.path.endsWith('/rest/v1/rpc/join_couple')) {
          rpcCalled = true;
          final body = decodeBody(options);
          expect(body['p_invite_code'], 'A7K2Q9X4');
          expect(body['p_user'], 'user-002');
          return textResponse('"c1"');
        }
        if (options.uri.path.endsWith('/rest/v1/couples')) {
          return jsonResponse([
            {
              'id': 'c1',
              'user_a': 'user-001',
              'user_b': 'user-002',
              'invite_code': 'A7K2Q9X4',
            }
          ]);
        }
        return textResponse('null', status: 404);
      };
      final couple =
          await CoupleService(makeApi(adapter, tokens)).joinCouple('a7k2q9x4');
      expect(rpcCalled, isTrue);
      expect(couple.id, 'c1');
      expect(couple.userB, 'user-002');
    });
  });

  group('MomentService 编辑与评论', () {
    test('updateMoment 走 PATCH 并带 representation', () async {
      final adapter = FakeDioAdapter();
      final tokens = InMemoryTokenStore();
      adapter.onRequest = (options) {
        expect(options.method, 'PATCH');
        expect(options.uri.path, endsWith('/rest/v1/moments'));
        expect(options.uri.queryParameters['id'], 'eq.mom1');
        expect(options.headers['Prefer'], 'return=representation');
        final body = decodeBody(options);
        expect(body['content'], '改过的内容');
        expect(body['location_text'], '公司楼下');
        // 归属字段不出现在请求体里：客户端压根不该尝试改
        expect(body.containsKey('publisher_id'), isFalse);
        expect(body.containsKey('couple_id'), isFalse);
        return jsonResponse([
          {
            'id': 'mom1',
            'couple_id': 'c1',
            'publisher_id': 'u1',
            'content': '改过的内容',
            'location_text': '公司楼下',
            'created_at': '2026-10-29T10:00:00Z',
            'updated_at': '2026-10-29T18:00:00Z',
          }
        ]);
      };
      final m = await MomentService(makeApi(adapter, tokens))
          .updateMoment('mom1', content: '改过的内容', locationText: '公司楼下');
      expect(m.content, '改过的内容');
      expect(m.isEdited, isTrue);
    });

    test('updateMoment 无字段可改时直接抛错，不发请求', () async {
      final adapter = FakeDioAdapter();
      final api = makeApi(adapter, InMemoryTokenStore());
      expect(
        () => MomentService(api).updateMoment('mom1'),
        throwsA(isA<ArgumentError>()),
      );
      expect(adapter.requests, isEmpty);
    });

    test('addComment 写入 moment_comments 并回传行', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) {
        expect(options.uri.path, endsWith('/rest/v1/moment_comments'));
        final body = decodeBody(options);
        expect(body['moment_id'], 'mom1');
        expect(body['author_id'], 'u2');
        expect(body['parent_id'], 'cm0');
        return jsonResponse([
          {
            'id': 'cm1',
            'moment_id': 'mom1',
            'author_id': 'u2',
            'body': '回复',
            'parent_id': 'cm0',
          }
        ]);
      };
      final c = await MomentService(makeApi(adapter, InMemoryTokenStore()))
          .addComment('mom1', 'u2', '回复', parentId: 'cm0');
      expect(c.id, 'cm1');
      expect(c.parentId, 'cm0');
    });

    test('deleteComment 按 id 删除', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) {
        expect(options.method, 'DELETE');
        expect(options.uri.path, endsWith('/rest/v1/moment_comments'));
        expect(options.uri.queryParameters['id'], 'eq.cm1');
        return jsonResponse([]);
      };
      await MomentService(makeApi(adapter, InMemoryTokenStore()))
          .deleteComment('cm1');
      expect(adapter.requests, hasLength(1));
    });

    test('listMoments 带内嵌 select，一次取回媒体与评论', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) {
        expect(options.uri.path, endsWith('/rest/v1/moments'));
        expect(
          options.uri.queryParameters['select'],
          '*,moment_media(*),moment_comments(*)',
        );
        return jsonResponse([
          {
            'id': 'mom1',
            'couple_id': 'c1',
            'publisher_id': 'u1',
            'content': 'x',
            'moment_media': [
              {
                'id': 'mm1',
                'moment_id': 'mom1',
                'object_key': 'c1/a.jpg',
                'media_type': 'image',
              }
            ],
            'moment_comments': [
              {
                'id': 'cm1',
                'moment_id': 'mom1',
                'author_id': 'u2',
                'body': '好',
              }
            ],
          }
        ]);
      };
      final list =
          await MomentService(makeApi(adapter, InMemoryTokenStore()))
              .listMoments('c1');
      expect(list.single.media, hasLength(1));
      expect(list.single.comments, hasLength(1));
    });

    test('内嵌查询失败时降级为普通查询（库未执行 schema_v2）', () async {
      final adapter = FakeDioAdapter();
      var embeddedRequested = 0;
      adapter.onRequest = (options) {
        if (options.uri.queryParameters['select'] != null) {
          embeddedRequested++;
          return jsonResponse(
            {'code': '42P01', 'message': 'relation "moment_comments" does not exist'},
            status: 404,
          );
        }
        return jsonResponse([
          {
            'id': 'mom1',
            'couple_id': 'c1',
            'publisher_id': 'u1',
            'content': '老库数据',
          }
        ]);
      };
      final list =
          await MomentService(makeApi(adapter, InMemoryTokenStore()))
              .listMoments('c1');
      expect(embeddedRequested, 1);
      expect(list.single.content, '老库数据');
      expect(list.single.media, isEmpty);
    });
  });

  group('CoupleService 绑定门禁', () {
    test('myPairedCouple 在 user_b 为空时返回 null', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) => jsonResponse([
            {
              'id': 'c1',
              'user_a': 'u1',
              'invite_code': 'A7K2Q9X4',
            }
          ]);
      final svc = CoupleService(makeApi(adapter, InMemoryTokenStore()));
      expect(await svc.myCouple(), isNotNull);
      expect(await svc.myPairedCouple(), isNull);
    });

    test('setStartedOn 只 PATCH started_on 一列', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) {
        if (options.method == 'GET') {
          return jsonResponse([
            {
              'id': 'c1',
              'user_a': 'u1',
              'user_b': 'u2',
              'invite_code': 'A7K2Q9X4',
            }
          ]);
        }
        expect(options.method, 'PATCH');
        expect(options.uri.path, endsWith('/rest/v1/couples'));
        expect(options.headers['Prefer'], 'return=representation');
        final body = decodeBody(options);
        expect(body.keys, ['started_on']);
        expect(body['started_on'], '2025-08-02');
        return jsonResponse([
          {
            'id': 'c1',
            'user_a': 'u1',
            'user_b': 'u2',
            'invite_code': 'A7K2Q9X4',
            'started_on': '2025-08-02',
          }
        ]);
      };
      await CoupleService(makeApi(adapter, InMemoryTokenStore()))
          .setStartedOn(DateTime(2025, 8, 2));
    });
  });

  group('StorageService', () {
    test('getUploadSign 调用云函数并返回 url', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) {
        expect(options.uri.path, endsWith('/storage/get_upload_sign'));
        return jsonResponse({'url': 'https://signed.example/up'});
      };
      final api = makeApi(adapter, InMemoryTokenStore());
      final url = await StorageService(api).getUploadSign('c1/a.jpg');
      expect(url, 'https://signed.example/up');
    });

    test('getDownloadSign 调用云函数', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) {
        expect(options.uri.path, endsWith('/storage/get_download_sign'));
        final body = decodeBody(options);
        expect(body['objectKey'], 'c1/v.mp4');
        return jsonResponse({'url': 'https://signed.example/dl'});
      };
      final api = makeApi(adapter, InMemoryTokenStore());
      final url = await StorageService(api).getDownloadSign('c1/v.mp4');
      expect(url, 'https://signed.example/dl');
    });

    test('deleteObject 调用云函数', () async {
      final adapter = FakeDioAdapter();
      adapter.onRequest = (options) {
        expect(options.uri.path, endsWith('/storage/delete_object'));
        return jsonResponse({'ok': true});
      };
      final api = makeApi(adapter, InMemoryTokenStore());
      await StorageService(api).deleteObject('c1/a.jpg');
      expect(adapter.requests, hasLength(1));
    });

    test('buildObjectKey 拼接 coupleId/uuid.ext', () {
      expect(
        StorageService.buildObjectKey('c1', 'fid', '.jpg'),
        'c1/fid.jpg',
      );
    });
  });
}
