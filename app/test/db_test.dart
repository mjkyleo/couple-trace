import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_app/db/app_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('upsertMoments 后可查询并按时间倒序', () async {
    final now = DateTime.now();
    await db.upsertMoments([
      LocalMoment(
        id: 'm1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: '第一条',
        createdAt: now.subtract(const Duration(hours: 2)),
        updatedAt: now,
      ),
      LocalMoment(
        id: 'm2',
        coupleId: 'c1',
        publisherId: 'u2',
        content: '第二条',
        createdAt: now,
        updatedAt: now,
      ),
    ]);
    final rows = await db.cachedMoments('c1');
    expect(rows, hasLength(2));
    expect(rows.first.id, 'm2'); // 倒序
  });

  test('同 id 重复 upsert 覆盖不重复', () async {
    await db.upsertMoments([
      LocalMoment(
        id: 'm1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: 'v1',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    ]);
    await db.upsertMoments([
      LocalMoment(
        id: 'm1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: 'v2',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 2),
      ),
    ]);
    final rows = await db.cachedMoments('c1');
    expect(rows, hasLength(1));
    expect(rows.first.content, 'v2');
  });

  test('媒体缓存标记与移除', () async {
    await db.upsertMoments([
      LocalMoment(
        id: 'm1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: 'x',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    ]);
    await db.upsertMedia([
      LocalMomentMediaData(
        id: 'media1',
        momentId: 'm1',
        objectKey: 'c1/a.jpg',
        mediaType: 'image',
        sort: 0,
        isCached: false,
      ),
    ]);

    var media = await db.mediaOf('m1');
    expect(media, hasLength(1));
    expect(media.first.isCached, isFalse);

    await db.markMediaCached('media1', true);
    media = await db.mediaOf('m1');
    expect(media.first.isCached, isTrue);

    await db.removeMoment('m1');
    expect(await db.mediaOf('m1'), isEmpty);
    expect(await db.cachedMoments('c1'), isEmpty);
  });

  test('clearAll 清空缓存表', () async {
    await db.upsertMoments([
      LocalMoment(
        id: 'm1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: 'x',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    ]);
    await db.clearAll();
    expect(await db.cachedMoments('c1'), isEmpty);
  });

  test('评论按时间正序缓存，删除动态时一并清掉', () async {
    await db.upsertMoments([
      LocalMoment(
        id: 'm1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: 'x',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    ]);
    await db.upsertComments([
      LocalMomentComment(
        id: 'c2',
        momentId: 'm1',
        authorId: 'u2',
        body: '回复',
        parentId: 'c1',
        createdAt: DateTime(2026, 10, 1, 12),
      ),
      LocalMomentComment(
        id: 'c1',
        momentId: 'm1',
        authorId: 'u1',
        body: '首评',
        createdAt: DateTime(2026, 10, 1, 10),
      ),
    ]);
    var rows = await db.commentsOf('m1');
    expect(rows.map((r) => r.id), ['c1', 'c2']); // 正序
    expect(rows.last.parentId, 'c1');

    await db.removeComment('c1');
    expect(await db.commentsOf('m1'), hasLength(1));

    await db.removeMoment('m1');
    expect(await db.commentsOf('m1'), isEmpty);
  });

  test('定位列可写入并读回', () async {
    await db.upsertMoments([
      LocalMoment(
        id: 'm1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: 'x',
        locationText: '公司楼下 · 馄饨摊',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    ]);
    final rows = await db.cachedMoments('c1');
    expect(rows.single.locationText, '公司楼下 · 馄饨摊');
  });

  test('偏好设置同 key 覆盖，且不随 clearAll 丢失', () async {
    expect(await db.pref('theme_accent'), isNull);
    await db.setPref('theme_accent', 'FF2F5D8C');
    await db.setPref('text_scale', 'large');
    expect(await db.pref('theme_accent'), 'FF2F5D8C');

    await db.setPref('theme_accent', 'FFC08A18');
    expect(await db.pref('theme_accent'), 'FFC08A18');

    await db.upsertMoments([
      LocalMoment(
        id: 'm1',
        coupleId: 'c1',
        publisherId: 'u1',
        content: 'x',
        createdAt: DateTime(2026, 10, 1),
        updatedAt: DateTime(2026, 10, 1),
      ),
    ]);
    await db.clearAll();
    // 「清理本地缓存」不该把用户的观感设置一起清掉
    expect(await db.pref('theme_accent'), 'FFC08A18');
    expect(await db.cachedMoments('c1'), isEmpty);

    await db.removePref('theme_accent');
    expect(await db.pref('theme_accent'), isNull);
  });
}
