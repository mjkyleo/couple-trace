import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Trace · 同迹 本地缓存数据库（Drift / SQLite）。
/// 仅用于离线浏览加速；权威数据始终以云端 PostgreSQL 为准。
@DriftDatabase(tables: [LocalMoments, LocalMomentMedia])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'trace_cache'));

  @override
  int get schemaVersion => 1;

  // ---- 动态缓存 ----

  Future<List<LocalMoment>> cachedMoments(String coupleId,
      {int limit = 100}) {
    return (select(localMoments)
          ..where((t) => t.coupleId.equals(coupleId))
          ..orderBy([(t) => OrderingTerm.desc(t.createdAt)])
          ..limit(limit))
        .get();
  }

  Future<void> upsertMoments(List<LocalMoment> moments) async {
    await batch((b) {
      b.insertAll(
        localMoments,
        moments,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<void> upsertMedia(List<LocalMomentMediaData> media) async {
    await batch((b) {
      b.insertAll(
        localMomentMedia,
        media,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<List<LocalMomentMediaData>> mediaOf(String momentId) {
    return (select(localMomentMedia)
          ..where((t) => t.momentId.equals(momentId))
          ..orderBy([(t) => OrderingTerm.asc(t.sort)]))
        .get();
  }

  Future<void> markMediaCached(String mediaId, bool cached) async {
    await (update(localMomentMedia)..where((t) => t.id.equals(mediaId)))
        .write(LocalMomentMediaCompanion(isCached: Value(cached)));
  }

  Future<void> removeMoment(String momentId) async {
    await (delete(localMomentMedia)..where((t) => t.momentId.equals(momentId)))
        .go();
    await (delete(localMoments)..where((t) => t.id.equals(momentId))).go();
  }

  /// 手动清理：清空本地缓存表
  Future<void> clearAll() async {
    await (delete(localMomentMedia)).go();
    await (delete(localMoments)).go();
  }
}
