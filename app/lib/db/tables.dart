import 'package:drift/drift.dart';

/// 本地缓存：动态主表（权威数据在云端，本地仅作离线缓存）
class LocalMoments extends Table {
  TextColumn get id => text()();
  TextColumn get coupleId => text()();
  TextColumn get publisherId => text()();
  TextColumn get content => text().nullable()();
  TextColumn get locationText => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 本地缓存：评论（parent_id 为空是评论，非空是对评论的回复）
class LocalMomentComments extends Table {
  TextColumn get id => text()();
  TextColumn get momentId => text()();
  TextColumn get authorId => text()();
  TextColumn get parentId => text().nullable()();
  TextColumn get body => text()();
  DateTimeColumn get createdAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// 本地个性化偏好：每对情侣独立部署，观感设置只属于这台设备，
/// 不上云（云里只留纪念日这类双方共享的数据）。
class LocalPrefs extends Table {
  TextColumn get prefKey => text()();
  TextColumn get prefValue => text()();

  @override
  Set<Column<Object>> get primaryKey => {prefKey};
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
