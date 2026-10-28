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
}
