import 'package:drift/drift.dart';

/// 本地缓存：动态主表（权威数据在云端，本地仅作离线缓存）
class LocalMoments extends Table {
  TextColumn get id => text()();
  TextColumn get coupleId => text()();
  TextColumn get publisherId => text()();
  TextColumn get content => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 本地缓存：动态媒体表
/// [isCached] 标记媒体文件是否已下载到 App 沙盒
class LocalMomentMedia extends Table {
  TextColumn get id => text()();
  TextColumn get momentId => text()();
  TextColumn get objectKey => text()();
  TextColumn get storageProvider => text().nullable()();
  TextColumn get mediaType => text()();
  IntColumn get sort => integer().withDefault(const Constant(0))();
  BoolColumn get isCached => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
