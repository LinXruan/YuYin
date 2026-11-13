part of '../../agent_automation_server.dart';

/// mock login 端点处理。
extension AgentMockLoginHandlers on AgentAutomationServer {
  /// POST /api/login/mock：动态模拟设置本地登录状态（用于自动化测试）
  Future<void> _handleMockLogin(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final mockLoggedIn = body['loggedIn'] == true;
    if (mockLoggedIn) {
      await LoginStateStore.markLoggedIn();
      loggedIn.value = true;
      logs.add('[AgentBridge] 已模拟设置为登录状态 (loggedIn=true)');
    } else {
      await LoginStateStore.clearLogin();
      loggedIn.value = false;
      logs.add('[AgentBridge] 已清除登录状态 (loggedIn=false)');
    }
    _sendJson(request, HttpStatus.ok, {
      'success': true,
      'loggedIn': loggedIn.value,
      'message': '登录状态已更新为: ${loggedIn.value}',
    });
  }

}
