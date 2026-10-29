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
