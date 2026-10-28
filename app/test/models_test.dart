import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:trace_app/models/models.dart';

void main() {
  group('MomentMedia.fromJson', () {
    test('解析图片媒体', () {
      final media = MomentMedia.fromJson({
        'id': 'm1',
        'moment_id': 'mm1',
        'object_key': 'c1/a.jpg',
        'storage_provider': 'cos',
        'media_type': 'image',
        'sort': 0,
      });
      expect(media.id, 'm1');
      expect(media.momentId, 'mm1');
      expect(media.objectKey, 'c1/a.jpg');
      expect(media.storageProvider, 'cos');
      expect(media.mediaType, 'image');
      expect(media.sort, 0);
    });

    test('缺失可选字段时使用默认值', () {
      final media = MomentMedia.fromJson({
        'id': 'm2',
        'moment_id': 'mm2',
        'object_key': 'c1/v.mp4',
        'media_type': 'video',
      });
      expect(media.storageProvider, isNull);
      expect(media.sort, 0);
    });

    test('toJson 可回环', () {
      final media = MomentMedia.fromJson({
        'id': 'm3',
        'moment_id': 'mm3',
        'object_key': 'c1/b.jpg',
        'storage_provider': 's3',
        'media_type': 'image',
        'sort': 2,
      });
      final json = media.toJson();
      expect(json['object_key'], 'c1/b.jpg');
      expect(json['media_type'], 'image');
    });
  });

  group('Moment.fromJson', () {
    test('解析动态与时间', () {
      final m = Moment.fromJson({
        'id': 'mom1',
        'couple_id': 'c1',
        'publisher_id': 'u1',
        'content': '今天东湖散步',
        'created_at': '2026-10-29T10:00:00+08:00',
      });
      expect(m.coupleId, 'c1');
      expect(m.content, '今天东湖散步');
      expect(m.createdAt, isNotNull);
    });

    test('copyWith 替换媒体列表', () {
      final m = Moment(
        id: 'mom1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: 'x',
      );
      final withMedia = m.copyWith(media: const [
        MomentMedia(
          id: 'mm1',
          momentId: 'mom1',
          objectKey: 'c1/a.jpg',
          mediaType: 'image',
        ),
      ]);
      expect(withMedia.media, hasLength(1));
      expect(m.media, isEmpty);
    });
  });

  group('Couple.fromJson', () {
    test('解析绑定关系', () {
      final c = Couple.fromJson({
        'id': 'c1',
        'user_a': 'u1',
        'user_b': 'u2',
        'invite_code': 'A7K2Q9X4',
        'created_at': '2026-10-01T00:00:00Z',
      });
      expect(c.inviteCode, 'A7K2Q9X4');
      expect(c.userA, 'u1');
      expect(c.userB, 'u2');
      expect(c.createdAt, isNotNull);
    });
  });

  group('JSON 编解码工具', () {
    test('jsonEncode/jsonDecode 正常工作', () {
      final decoded = jsonDecode('{"a":1,"b":[1,2]}') as Map<String, dynamic>;
      expect(decoded['a'], 1);
      expect(decoded['b'], [1, 2]);
    });
  });
}
