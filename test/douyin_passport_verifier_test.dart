import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/auth/auth_models.dart';
import 'package:yuyin/services/auth/douyin_passport_verifier.dart';

class MockDioAdapter implements HttpClientAdapter {
  int statusCode = 200;
  Map<String, dynamic> responseBody = {};
  bool throwNetworkError = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    if (throwNetworkError) {
      throw DioException(
        requestOptions: options,
        error: 'Network connection failed',
        type: DioExceptionType.connectionError,
      );
    }

    final bytes = utf8.encode(jsonEncode(responseBody));
    return ResponseBody.fromBytes(
      bytes,
      statusCode,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('DouyinPassportVerifier 权威核验器测试', () {
    late Dio dio;
    late MockDioAdapter adapter;
    late DouyinPassportVerifier verifier;

    setUp(() {
      dio = Dio();
      adapter = MockDioAdapter();
      dio.httpClientAdapter = adapter;
      verifier = DouyinPassportVerifier(dio: dio);
    });

    test('Cookie 为空时直接返回 invalid', () async {
      final res = await verifier.verify('');
      expect(res.status, RemoteVerifyStatus.invalid);
    });

    test('服务端返回合法 UID 判定为 valid', () async {
      adapter.responseBody = {
        'data': {
          'user_id': 987654321,
          'error_code': 0,
        },
      };

      final res = await verifier.verify('sessionid=123');
      expect(res.status, RemoteVerifyStatus.valid);
      expect(res.userId, '987654321');
    });

    test('服务端返回 error_code 101 / 未登录判定为 invalid', () async {
      adapter.responseBody = {
        'data': {
          'description': '用户未登录',
          'error_code': 101,
        },
      };

      final res = await verifier.verify('sessionid=123');
      expect(res.status, RemoteVerifyStatus.invalid);
    });

    test('HTTP 401 判定为 invalid', () async {
      adapter.statusCode = 401;
      adapter.responseBody = {'message': 'Unauthorized'};

      final res = await verifier.verify('sessionid=123');
      expect(res.status, RemoteVerifyStatus.invalid);
    });

    test('网络连接异常判定为 networkError 容灾', () async {
      adapter.throwNetworkError = true;

      final res = await verifier.verify('sessionid=123');
      expect(res.status, RemoteVerifyStatus.networkError);
    });
  });
}

