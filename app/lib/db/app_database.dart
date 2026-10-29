import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

part 'app_database.g.dart';

/// Trace · 同迹 本地缓存数据库（Drift / SQLite）。
/// 仅用于离线浏览加速与本地个性化偏好；权威数据始终以云端 PostgreSQL 为准。
@DriftDatabase(
  tables: [LocalMoments, LocalMomentMedia, LocalMomentComments, LocalPrefs],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'trace_cache'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => m.createAll(),
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // v1 -> v2：动态加定位列，新增评论表与偏好表
            await m.addColumn(localMoments, localMoments.locationText);
            await m.createTable(localMomentComments);
            await m.createTable(localPrefs);
          }
        },
      );

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
    await (delete(localMomentComments)
          ..where((t) => t.momentId.equals(momentId)))
        .go();
    await (delete(localMoments)..where((t) => t.id.equals(momentId))).go();
  }

  // ---- 评论缓存 ----

  Future<void> upsertComments(List<LocalMomentComment> comments) async {
    await batch((b) {
      b.insertAll(
        localMomentComments,
        comments,
        mode: InsertMode.insertOrReplace,
      );
    });
  }

  Future<List<LocalMomentComment>> commentsOf(String momentId) {
    return (select(localMomentComments)
          ..where((t) => t.momentId.equals(momentId))
          ..orderBy([(t) => OrderingTerm.asc(t.createdAt)]))
        .get();
  }

  Future<void> removeComment(String commentId) async {
    await (delete(localMomentComments)..where((t) => t.id.equals(commentId)))
        .go();
  }

  // ---- 个性化偏好（不参与"清理缓存"） ----

  Future<String?> pref(String key) async {
    final row = await (select(localPrefs)
          ..where((t) => t.prefKey.equals(key))
          ..limit(1))
        .getSingleOrNull();
    return row?.prefValue;
  }

  Future<void> setPref(String key, String value) async {
    await into(localPrefs).insert(
      LocalPref(prefKey: key, prefValue: value),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<void> removePref(String key) async {
    await (delete(localPrefs)..where((t) => t.prefKey.equals(key))).go();
  }

  /// 手动清理：清空本地缓存表（偏好设置保留，云端文件不动）
  Future<void> clearAll() async {
    await (delete(localMomentMedia)).go();
    await (delete(localMomentComments)).go();
    await (delete(localMoments)).go();
  }
}
