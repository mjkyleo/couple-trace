import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// 可编程的 Dio HttpClientAdapter，用于在测试中捕获请求并返回预设响应。
class FakeDioAdapter implements HttpClientAdapter {
  final List<RequestOptions> requests = [];

  /// 返回响应文本；默认返回空 JSON 数组（PostgREST 风格）
  ResponseBody Function(RequestOptions options)? onRequest;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    final handler = onRequest;
    if (handler != null) {
      return handler(options);
    }
    return ResponseBody.fromString(
      '[]',
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

/// 生成一个 JWT 样式的令牌（仅用于测试 currentUserId 解析，非真实签名）
String makeTestJwt(String sub) {
  String enc(String s) =>
      base64UrlEncode(utf8.encode(s)).replaceAll('=', '');
  return '${enc('{"alg":"HS256","typ":"JWT"}')}.'
      '${enc('{"sub":"$sub"}')}.'
      'test-signature';
}

ResponseBody jsonResponse(Object data, {int status = 200}) {
  return ResponseBody.fromString(
    jsonEncode(data),
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}

ResponseBody textResponse(String body, {int status = 200}) {
  return ResponseBody.fromString(
    body,
    status,
    headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    },
  );
}
