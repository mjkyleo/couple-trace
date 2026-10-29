import 'dart:convert';

import 'package:dio/dio.dart';

import 'app_config.dart';
import 'token_store.dart';

/// 统一 HTTP 客户端。
/// - 认证接口：`/auth/v1/*`
/// - 数据库接口（PostgREST）：`/rest/v1/*`
/// - 存储云函数接口：`{storageFnUrl}/storage/*`
class ApiClient {
  ApiClient({
    required this._dio,
    required this._tokens,
    String? supabaseUrl,
    String? anonKey,
  }) : _supabaseUrl = supabaseUrl ?? AppConfig.supabaseUrl,
       _anonKey = anonKey ?? AppConfig.supabaseAnonKey;

  final Dio _dio;
  final TokenStore _tokens;
  final String _supabaseUrl;
  final String _anonKey;

  /// 当前登录用户 id（从 JWT payload 的 sub 解析）
  String? get currentUserId {
    final token = _tokens.lastRead;
    if (token == null || token.isEmpty) return null;
    final parts = token.split('.');
    if (parts.length < 2) return null;
    try {
      final base64 = parts[1].replaceAll('-', '+').replaceAll('_', '/');
      final padded = base64.padRight(
        base64.length + (4 - base64.length % 4) % 4,
        '=',
      );
      final decoded = utf8.decode(base64Url.decode(padded));
      final map = jsonDecode(decoded) as Map<String, dynamic>;
      final sub = map['sub'];
      return sub is String ? sub : null;
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> _headers({bool auth = true}) => {
    'apikey': _anonKey,
    'Content-Type': 'application/json',
    if (auth) ...?_authHeader(),
  };

  Map<String, String>? _authHeader() {
    final token = _tokens.lastRead;
    if (token == null || token.isEmpty) return null;
    return {'Authorization': 'Bearer $token'};
  }

  // ---- 认证接口 ----

  Future<Map<String, dynamic>> signUp(String email, String password) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_supabaseUrl/auth/v1/signup',
      data: {'email': email, 'password': password},
      options: Options(headers: _headers(auth: false)),
    );
    return res.data ?? const {};
  }

  Future<Map<String, dynamic>> signIn(String email, String password) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '$_supabaseUrl/auth/v1/token?grant_type=password',
      data: {'email': email, 'password': password},
      options: Options(headers: _headers(auth: false)),
    );
    final token = res.data?['access_token'] as String?;
    if (token != null && token.isNotEmpty) {
      await _tokens.write(token);
    }
    return res.data ?? const {};
  }

  Future<void> signOut() async {
    await _tokens.clear();
  }

  // ---- 数据库接口（PostgREST）----

  Future<List<dynamic>> dbGet(
    String table, {
    Map<String, String>? query,
  }) async {
    final res = await _dio.get<List<dynamic>>(
      '$_supabaseUrl/rest/v1/$table',
      queryParameters: query,
      options: Options(headers: _headers()),
    );
    return res.data ?? const [];
  }

  /// 写入一行并取回真实数据。
  /// 必须带 `Prefer: return=representation`：PostgREST 默认响应体为空，
  /// 少了这个头，调用方拿到空 Map 后在 fromJson 的强转处必挂。
  Future<Map<String, dynamic>> dbInsert(
    String table,
    Map<String, dynamic> body,
  ) async {
    final res = await _dio.post<dynamic>(
      '$_supabaseUrl/rest/v1/$table',
      data: body,
      options: Options(
        headers: {..._headers(), 'Prefer': 'return=representation'},
      ),
    );
    return _singleRow(res.data, table);
  }

  static Map<String, dynamic> _singleRow(dynamic data, String table) {
    if (data is List) {
      if (data.isEmpty || data.first is! Map) {
        throw Exception('insert returned no row: $table');
      }
      return Map<String, dynamic>.from(data.first as Map);
    }
    if (data is Map) return Map<String, dynamic>.from(data);
    throw Exception('insert returned no row: $table');
  }

  /// 按条件更新并取回更新后的行。
  /// 与 dbInsert 同理，不带 representation 则响应体为空。
  Future<Map<String, dynamic>> dbUpdate(
    String table, {
    required Map<String, String> query,
    required Map<String, dynamic> body,
  }) async {
    final res = await _dio.patch<dynamic>(
      '$_supabaseUrl/rest/v1/$table',
      queryParameters: query,
      data: body,
      options: Options(
        headers: {..._headers(), 'Prefer': 'return=representation'},
      ),
    );
    return _singleRow(res.data, table);
  }

  Future<void> dbDelete(
    String table, {
    required Map<String, String> query,
  }) async {
    await _dio.delete<void>(
      '$_supabaseUrl/rest/v1/$table',
      queryParameters: query,
      options: Options(headers: _headers()),
    );
  }

  /// 调用数据库 RPC 函数（如 join_couple）
  Future<dynamic> dbRpc(String fn, Map<String, dynamic> args) async {
    final res = await _dio.post<dynamic>(
      '$_supabaseUrl/rest/v1/rpc/$fn',
      data: args,
      options: Options(headers: _headers()),
    );
    return res.data;
  }

  // ---- 存储云函数接口 ----

  Future<Map<String, dynamic>> storageCall(
    String path,
    Map<String, dynamic> body,
  ) async {
    final res = await _dio.post<Map<String, dynamic>>(
      '${AppConfig.storageFnUrl}$path',
      data: body,
      options: Options(headers: _headers()),
    );
    return res.data ?? const {};
  }

  /// 用签名 URL 直接 PUT 上传文件
  Future<void> uploadToSignedUrl(String url, List<int> bytes) async {
    await _dio.put<void>(
      url,
      data: Stream.fromIterable([bytes]),
      options: Options(headers: {'Content-Type': 'application/octet-stream'}),
    );
  }

  /// 用签名 URL 下载文件到本地路径
  Future<void> downloadToFile(String url, String savePath) async {
    await _dio.download(url, savePath);
  }
}
