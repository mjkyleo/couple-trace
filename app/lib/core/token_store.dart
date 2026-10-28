import 'dart:async';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 认证令牌的持久化抽象。
/// 默认实现为文件存储；测试中可注入内存实现。
abstract class TokenStore {
  /// 最近一次读/写的令牌（同步访问，供 ApiClient 快速取用）
  String? get lastRead;

  Future<String?> read();
  Future<void> write(String token);
  Future<void> clear();
}

/// 内存实现（测试 / 调试用）
class InMemoryTokenStore implements TokenStore {
  String? _token;

  @override
  String? get lastRead => _token;

  @override
  Future<String?> read() async => _token;

  @override
  Future<void> write(String token) async => _token = token;

  @override
  Future<void> clear() async => _token = null;
}

/// 文件实现（默认，基于 path_provider）
class FileTokenStore implements TokenStore {
  FileTokenStore(this._file);

  final Future<File> _file;
  String? _cache;

  @override
  String? get lastRead => _cache;

  @override
  Future<String?> read() async {
    if (_cache != null) return _cache;
    final f = await _file;
    if (!await f.exists()) return null;
    _cache = await f.readAsString();
    return _cache;
  }

  @override
  Future<void> write(String token) async {
    _cache = token;
    final f = await _file;
    await f.writeAsString(token);
  }

  @override
  Future<void> clear() async {
    _cache = null;
    final f = await _file;
    if (await f.exists()) {
      await f.delete();
    }
  }
}

/// 文件存储工厂：使用应用支持目录下的 auth_token 文件
Future<FileTokenStore> createFileTokenStore() async {
  final dir = await getApplicationSupportDirectory();
  final file = File('${dir.path}/auth_token');
  return FileTokenStore(Future.value(file));
}
