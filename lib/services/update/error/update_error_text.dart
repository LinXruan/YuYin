// 网络异常文案清洗。
import 'dart:async';

import 'package:dio/dio.dart';
class UpdateErrorText {
  /// 将 Dio 网络异常清洗为简短友好的中文提示，杜绝底层英文 Socket/SSL 异常刷屏
  static String formatDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      return '连接 GitHub 超时，请检查网络或稍后重试';
    }
    if (e.type == DioExceptionType.connectionError) {
      return '网络连接异常，无法访问更新服务器';
    }
    if (e.type == DioExceptionType.badCertificate) {
      return '安全连接校验失败，请检查网络或系统时间';
    }
    if (e.type == DioExceptionType.badResponse) {
      final code = e.response?.statusCode;
      if (code == 403 || code == 429) {
        return 'GitHub 请求过于频繁，请稍后重试';
      }
      if (code == 404) {
        return '未找到更新发布信息，请稍后重试';
      }
      if (code != null && code >= 500) {
        return '更新服务器暂时不可用 ($code)，请稍后重试';
      }
      return '更新服务器响应异常${code != null ? " ($code)" : ""}';
    }

    final raw = '${e.error ?? ''} ${e.message ?? ''}'.toLowerCase();
    if (raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection') ||
        raw.contains('network is unreachable') ||
        raw.contains('handshake') ||
        raw.contains('tlsexception') ||
        raw.contains('httpexception') ||
        raw.contains('errno')) {
      return '网络连接异常，无法访问更新服务器';
    }
    return '检查更新失败，请稍后重试';
  }

  /// 将通用未知异常清洗为简短友好的中文提示
  static String formatUnknownError(Object error) {
    final raw = error.toString().toLowerCase();
    if (error is TimeoutException || raw.contains('timeout')) {
      return '连接 GitHub 超时，请检查网络或稍后重试';
    }
    if (raw.contains('socketexception') ||
        raw.contains('failed host lookup') ||
        raw.contains('connection') ||
        raw.contains('network is unreachable') ||
        raw.contains('handshake') ||
        raw.contains('tlsexception') ||
        raw.contains('httpexception')) {
      return '网络连接异常，无法访问更新服务器';
    }
    return '检查更新失败，请稍后重试';
  }
}
