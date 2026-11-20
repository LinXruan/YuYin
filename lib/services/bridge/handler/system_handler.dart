import 'dart:io';

import '../../../utils/login_state_store.dart';
import '../../../utils/settings/download_settings_store.dart';
import '../../download/download_cancel_registry.dart';
import '../server/agent_automation_server.dart';

/// 系统端点：取消任务、执行 JS、画质开关与登录态模拟。
class SystemHandler {
  SystemHandler(this.server);

  final AgentAutomationServer server;

  /// POST /api/cancel：取消当前进行中的任务
  Future<void> handleCancel(HttpRequest request) async {
    final downloadCancelled = DownloadCancelRegistry.cancel();
    server.sniffer?.cancelActiveTask();
    server.activeDownloadToken?.cancel('Agent 指令取消');
    server.activeDownloadToken = null;
    server.busy.value = false;
    server.logs.add(downloadCancelled ? '已取消保存' : '已取消解析');
    server.sendJson(request, HttpStatus.ok, {
      'success': true,
      'downloadCancelled': downloadCancelled,
    });
  }

  /// POST /api/eval：向捕获 WebView 注入并执行 JS 脚本
  Future<void> handleEval(HttpRequest request) async {
    final body = await server.readJsonBody(request);
    final script = body['script']?.toString();
    if (script == null || script.trim().isEmpty) {
      server.sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '缺少 script 参数', 'code': 400},
      );
      return;
    }

    final sniffer = server.sniffer;
    if (sniffer == null) {
      server.sendJson(
        request,
        HttpStatus.serviceUnavailable,
        {'error': 'Sniffer 服务未初始化', 'code': 503},
      );
      return;
    }

    try {
      final rawResult = await sniffer.controller.runJavaScriptReturningResult(
        script,
      );
      server.sendJson(request, HttpStatus.ok, {
        'success': true,
        'result': rawResult.toString(),
      });
    } catch (e) {
      server.sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': 'JS 执行失败: $e', 'code': 500},
      );
    }
  }

  /// POST /api/settings/quality：切换“仅显示同分辨率下最高画质”开关
  Future<void> handleQualitySetting(HttpRequest request) async {
    final body = await server.readJsonBody(request);
    final enabled = body['onlyHighestQualityPerResolution'];
    if (enabled is! bool) {
      server.sendJson(
        request,
        HttpStatus.badRequest,
        {
          'error': '缺少必要布尔参数: onlyHighestQualityPerResolution',
          'code': 400,
        },
      );
      return;
    }

    await DownloadSettingsStore.setOnlyHighestQualityPerResolution(enabled);
    server.sendJson(request, HttpStatus.ok, {
      'success': true,
      'onlyHighestQualityPerResolution':
          DownloadSettingsStore.onlyHighestQualityPerResolution,
    });
  }

  /// POST /api/login/mock：动态模拟设置本地登录状态（用于自动化测试）
  Future<void> handleMockLogin(HttpRequest request) async {
    final body = await server.readJsonBody(request);
    final mockLoggedIn = body['loggedIn'] == true;
    if (mockLoggedIn) {
      await LoginStateStore.markLoggedIn();
      server.loggedIn.value = true;
      server.logs.add('已模拟设置为登录状态 (loggedIn=true)');
    } else {
      await LoginStateStore.clearLogin();
      server.loggedIn.value = false;
      server.logs.add('已清除登录状态 (loggedIn=false)');
    }
    server.sendJson(request, HttpStatus.ok, {
      'success': true,
      'loggedIn': server.loggedIn.value,
      'message': '登录状态已更新为: ${server.loggedIn.value}',
    });
  }
}
