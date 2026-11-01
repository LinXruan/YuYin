import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// 全局网络状态探测工具
///
/// 通过网卡状态判断与快速轻量级 DNS/主机探测，
/// 毫秒级拦截无网络操作，为解析、登录、检查更新提供前置网络保护。
class NetworkDetector {
  NetworkDetector._();

  /// 快速探测当前设备是否已连接互联网
  ///
  /// 先检查本机物理/虚拟网卡接口是否有效，
  /// 再对国内高可用域名（如 douyin.com / baidu.com）进行快速轻量级解析。
  static Future<bool> hasInternetConnection({
    Duration timeout = const Duration(milliseconds: 2500),
  }) async {
    try {
      // 1. 本地内核级网卡检查：0 流量消耗，毫秒级快速返回
      final interfaces = await NetworkInterface.list(
        includeLoopback: false,
        type: InternetAddressType.any,
      );
      if (interfaces.isEmpty) {
        return false;
      }
      final hasActiveAddress = interfaces.any(
        (it) => it.addresses.any((addr) => !addr.isLoopback),
      );
      if (!hasActiveAddress) {
        return false;
      }

      // 2. 快速轻量级 DNS 解析测试
      final result = await InternetAddress.lookup('douyin.com')
          .timeout(timeout);
      if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
        return true;
      }
      return false;
    } on SocketException {
      return false;
    } on TimeoutException {
      // 超时情况下尝试备用高可用域名 baidu.com 快速确认
      try {
        final fallback = await InternetAddress.lookup('baidu.com')
            .timeout(const Duration(milliseconds: 1500));
        return fallback.isNotEmpty && fallback[0].rawAddress.isNotEmpty;
      } catch (_) {
        return false;
      }
    } catch (_) {
      return false;
    }
  }

  /// 弹出统一的“网络未连接”提示
  static void showOfflineSnackbar(
    BuildContext context, {
    String message = '网络未连接，请检查网络设置',
  }) {
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.wifi_off_rounded, size: 18, color: Colors.white),
            const SizedBox(width: 8),
            Expanded(child: Text(message)),
          ],
        ),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

