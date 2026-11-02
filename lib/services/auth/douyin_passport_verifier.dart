import 'dart:async';
import 'package:dio/dio.dart';

import '../douyin_sniffer.dart';
import 'auth_contracts.dart';
import 'auth_models.dart';

/// 抖音官方 Passport 账号信息权威鉴权器
class DouyinPassportVerifier implements IAuthRemoteVerifier {
  DouyinPassportVerifier({
    Dio? dio,
    this.endpoint = 'https://www.douyin.com/passport/web/account/info/',
    this.timeout = const Duration(seconds: 6),
  }) : _dio = dio ?? Dio();

  final Dio _dio;
  final String endpoint;
  final Duration timeout;

  @override
  Future<RemoteVerifyResult> verify(String cookieHeader) async {
    final cleanCookies = cookieHeader.trim();
    if (cleanCookies.isEmpty) {
      return RemoteVerifyResult.invalid(message: '本地无 Cookie 凭据');
    }

    try {
      final response = await _dio.get<dynamic>(
        endpoint,
        options: Options(
          headers: {
            'User-Agent': DouyinSniffer.desktopUserAgent,
            'Referer': 'https://www.douyin.com/',
            'Accept': 'application/json, text/plain, */*',
            'Cookie': cleanCookies,
          },
          sendTimeout: timeout,
          receiveTimeout: timeout,
          responseType: ResponseType.json,
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final statusCode = response.statusCode ?? 0;
      if (statusCode == 401 || statusCode == 403) {
        return RemoteVerifyResult.invalid(
          message: '服务端明确拒绝鉴权 (HTTP $statusCode)',
        );
      }

      final data = response.data;
      if (data is! Map) {
        return RemoteVerifyResult.networkError(message: '响应数据格式异常');
      }

      final d = data['data'] is Map
          ? Map<String, dynamic>.from(data['data'] as Map)
          : Map<String, dynamic>.from(data);

      final errorCode = d['error_code'] ?? d['errorCode'];
      final description = d['description']?.toString() ?? '';

      // 明确未登录状态码 (101) 或包含“未登录”字样
      if (errorCode == 101 ||
          errorCode == '101' ||
          description.contains('未登录') ||
          description.contains('not login')) {
        return RemoteVerifyResult.invalid(
          message: description.isNotEmpty ? description : '服务端报告未登录 (101)',
        );
      }

      // 成功状态且带有有效 UID
      final rawUid = d['user_id'] ?? d['userId'] ?? d['uid'];
      if (rawUid != null) {
        final uidStr = rawUid.toString().trim();
        if (RegExp(r'^\d{5,25}$').hasMatch(uidStr) && uidStr != '0') {
          return RemoteVerifyResult.valid(userId: uidStr);
        }
      }

      // 如果有非 0 错误码且非二维码接口
      if (errorCode != null && errorCode != 0 && errorCode != '0') {
        return RemoteVerifyResult.invalid(
          message: description.isNotEmpty ? description : '错误码: $errorCode',
        );
      }

      // 其余兜底视为无效
      return RemoteVerifyResult.invalid(message: '响应未包含有效已登录用户数据');
    } on DioException catch (e) {
      // 网络层异常（超时/断网/连接重置）：归入容灾网络错误，不误清登录状态
      return RemoteVerifyResult.networkError(
        message: e.message ?? '网络连接超时或不可用',
      );
    } catch (e) {
      return RemoteVerifyResult.networkError(message: '$e');
    }
  }
}

