import 'dart:convert';
import 'dart:developer' as developer;

import 'package:dio/dio.dart';

/// 把底层异常翻成给用户看的一句话。
/// 原文只进日志（`flutter run` 控制台 / logcat），不上界面 ——
/// 之前页面直接 `e.toString()`，用户会看到
/// `DioException [connection error]: ... errno = 7` 这种东西。
String describeError(Object e, {String fallback = '操作没成功，稍后再试'}) {
  developer.log('$e', name: 'trace.error');
  if (e is DioException) return _describeDio(e, fallback);
  return fallback;
}

String _describeDio(DioException e, String fallback) => switch (e.type) {
  DioExceptionType.connectionTimeout ||
  DioExceptionType.sendTimeout ||
  DioExceptionType.receiveTimeout ||
  DioExceptionType.transformTimeout => '网络超时了，稍后再试',
  DioExceptionType.connectionError => '连不上服务器，检查一下网络再试',
  DioExceptionType.badCertificate => '服务器证书校验没通过',
  DioExceptionType.cancel => '已取消',
  DioExceptionType.badResponse => _describeStatus(e.response, fallback),
  DioExceptionType.unknown => fallback,
};

String _describeStatus(Response? res, String fallback) {
  final fromServer = _serverMessage(res?.data);
  if (fromServer != null) return fromServer;
  final code = res?.statusCode;
  if (code == null) return fallback;
  if (code == 401 || code == 403) return '没有权限，重新登录后再试';
  if (code == 404) return '没找到对应的内容';
  if (code == 429) return '操作太频繁，稍后再试';
  if (code >= 500) return '服务器开小差了，稍后再试';
  return '填写的内容没被接受，检查一下再试';
}

/// 只认 MemFire/GoTrue 与 PostgREST 稳定返回的字段，翻不出来的不猜
String? _serverMessage(Object? body) {
  Map? map;
  if (body is Map) {
    map = body;
  } else if (body is String) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) map = decoded;
    } on FormatException {
      return null;
    }
  }
  if (map == null) return null;
  final hint = [
    map['error_description'],
    map['error_code'],
    map['msg'],
  ].whereType<String>().join(' ').toLowerCase();
  if (hint.contains('invalid login credentials')) return '邮箱或密码不正确';
  if (hint.contains('already registered') || hint.contains('already exists')) {
    return '这个邮箱已经注册过了';
  }
  if (hint.contains('password')) return '密码不符合要求，至少 6 位';
  if (hint.contains('rate limit') || hint.contains('over request limit')) {
    return '操作太频繁，稍后再试';
  }
  if (hint.contains('row-level security')) return '没有权限，重新登录后再试';
  return null;
}
