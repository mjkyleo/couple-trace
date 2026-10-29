import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:trace_app/core/error_text.dart';

DioException _dio(
  DioExceptionType type, {
  int? status,
  Object? body,
}) => DioException(
  type: type,
  requestOptions: RequestOptions(path: '/rest/v1/moments'),
  response: status == null
      ? null
      : Response(
          requestOptions: RequestOptions(path: '/rest/v1/moments'),
          statusCode: status,
          data: body,
        ),
);

void main() {
  // 反向断言：界面上任何时候都不该再出现底层原文
  void expectNoRawText(String text) {
    expect(text, isNot(contains('DioException')));
    expect(text, isNot(contains('errno')));
    expect(text, isNot(contains('SocketException')));
  }

  test('连接失败翻成网络提示，不吐 errno', () {
    final t = describeError(
      _dio(DioExceptionType.connectionError),
    );
    expect(t, '连不上服务器，检查一下网络再试');
    expectNoRawText(t);
  });

  test('三类超时统一翻成超时', () {
    for (final type in [
      DioExceptionType.connectionTimeout,
      DioExceptionType.sendTimeout,
      DioExceptionType.receiveTimeout,
    ]) {
      expect(describeError(_dio(type)), '网络超时了，稍后再试');
    }
  });

  test('401/403 翻成重新登录', () {
    expect(describeError(_dio(DioExceptionType.badResponse, status: 401)),
        '没有权限，重新登录后再试');
    expect(describeError(_dio(DioExceptionType.badResponse, status: 403)),
        '没有权限，重新登录后再试');
  });

  test('GoTrue 的登录失败翻成人话', () {
    final t = describeError(
      _dio(
        DioExceptionType.badResponse,
        status: 400,
        body: {'error_description': 'Invalid login credentials'},
      ),
    );
    expect(t, '邮箱或密码不正确');
    expectNoRawText(t);
  });

  test('响应体是 JSON 字符串也能认出来', () {
    final t = describeError(
      _dio(
        DioExceptionType.badResponse,
        status: 422,
        body: '{"error_description":"Email already registered"}',
      ),
    );
    expect(t, '这个邮箱已经注册过了');
  });

  test('5xx 与 RLS 拒绝各有说法', () {
    expect(describeError(_dio(DioExceptionType.badResponse, status: 503)),
        '服务器开小差了，稍后再试');
    // 状态码给的是 400，只能靠响应体认出这是 RLS 拒绝
    expect(
      describeError(
        _dio(
          DioExceptionType.badResponse,
          status: 400,
          body: {'error_description': 'new row violates row-level security policy'},
        ),
      ),
      '没有权限，重新登录后再试',
    );
  });

  test('认不出的 4xx 不猜具体原因', () {
    expect(describeError(_dio(DioExceptionType.badResponse, status: 400)),
        '填写的内容没被接受，检查一下再试');
  });

  test('非 Dio 异常走 fallback，不抛', () {
    expect(describeError(Exception('boom'), fallback: '稍后再试'), '稍后再试');
    expect(describeError(StateError('bad state')), '操作没成功，稍后再试');
  });

  test('响应体是坏 JSON 也只是回退，不炸', () {
    final t = describeError(
      _dio(
        DioExceptionType.badResponse,
        status: 500,
        body: '<html>not json</html>',
      ),
    );
    expect(t, '服务器开小差了，稍后再试');
  });
}
