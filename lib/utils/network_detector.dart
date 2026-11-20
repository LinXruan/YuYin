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

      // 2. 并发解析两个高可用域名，整体受 timeout 约束
      final results = await Future.wait([
        _resolves('douyin.com'),
        _resolves('baidu.com'),
      ]).timeout(timeout, onTimeout: () => const [false, false]);
      return results.any((reachable) => reachable);
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _resolves(String host) async {
    try {
      final result = await InternetAddress.lookup(host);
      return result.any((addr) => isUsableAddress(addr));
    } catch (_) {
      return false;
    }
  }

  /// 排除回环、link-local（169.254/fe80::）与未指定地址，避免断网时误判为在线
  @visibleForTesting
  static bool isUsableAddress(InternetAddress address) {
    if (address.isLoopback) return false;
    final bytes = address.rawAddress;
    if (address.type == InternetAddressType.IPv4 && bytes.length == 4) {
      if (bytes[0] == 0) return false;
      if (bytes[0] == 169 && bytes[1] == 254) return false;
      return true;
    }
    if (address.type == InternetAddressType.IPv6 && bytes.length == 16) {
      if (bytes[0] == 0xfe && (bytes[1] & 0xc0) == 0x80) return false;
      return true;
    }
    return true;
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