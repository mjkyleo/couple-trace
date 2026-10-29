import 'dart:io';

import 'package:path_provider/path_provider.dart';

import '../core/api_client.dart';
import '../db/app_database.dart';

/// 本地媒体缓存服务：
/// - 媒体文件缓存到 App 沙盒目录
/// - 已缓存文件优先本地读取，无缓存时才向云函数申请签名 URL 下载
/// - 支持手动清理（只删本地，云端文件保留）
class CacheService {
  CacheService(this._api, this._db, {this._cacheDir});
  final ApiClient _api;
  final AppDatabase _db;
  Directory? _cacheDir;

  Future<Directory> _dir() async {
    if (_cacheDir != null) return _cacheDir!;
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory('${docs.path}/media_cache');
    await dir.create(recursive: true);
    _cacheDir = dir;
    return dir;
  }

  Future<String> _pathFor(String objectKey) async {
    final dir = await _dir();
    // objectKey 已经过服务端校验（无 ..、无绝对路径），此处再兜底清洗
    final safe = objectKey.replaceAll(RegExp(r'[^A-Za-z0-9._/-]'), '_');
    final file = File('${dir.path}/$safe');
    await file.parent.create(recursive: true);
    return file.path;
  }

  /// 本地是否已存在该媒体
  Future<bool> exists(String objectKey) async {
    final path = await _pathFor(objectKey);
    return File(path).exists();
  }

  /// 取媒体本地路径；不存在则通过签名 URL 下载后返回
  Future<String> resolve(String objectKey) async {
    final path = await _pathFor(objectKey);
    if (await File(path).exists()) return path;
    final url = await _signedUrl(objectKey);
    await _api.downloadToFile(url, path);
    return path;
  }

  final Map<String, String> _urlCache = {};

  /// 列表页缩略图直接走签名 URL，不强制下载到沙盒；
  /// 签名 30 分钟有效，同一 key 在有效期内复用，避免逐条重复申请。
  Future<String> signedUrl(String objectKey) async {
    final cached = _urlCache[objectKey];
    if (cached != null) return cached;
    final url = await _signedUrl(objectKey);
    _urlCache[objectKey] = url;
    return url;
  }

  Future<String> _signedUrl(String objectKey) async {
    final res = await _api.storageCall(
      '/storage/get_download_sign',
      {'objectKey': objectKey},
    );
    final url = res['url'];
    if (url is! String || url.isEmpty) {
      throw Exception('empty download url for $objectKey');
    }
    return url;
  }

  /// 手动清理本地媒体缓存与本地缓存表（云端不受影响）
  Future<void> clearCache() async {
    _urlCache.clear();
    final dir = await _dir();
    if (dir.existsSync()) {
      dir.deleteSync(recursive: true);
    }
    await dir.create(recursive: true);
    await _db.clearAll();
  }
}
