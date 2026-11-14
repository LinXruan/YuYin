part of '../server/agent_automation_server.dart';

/// display 端点处理。
extension AgentDisplayHandlers on AgentAutomationServer {
  Future<void> _handleGetDisplay(HttpRequest request) async {
    _sendJson(request, HttpStatus.ok, {
      'activeRefreshRate': DisplayModeService.activeRefreshRate,
      'maxRefreshRate': DisplayModeService.maxRefreshRate,
      'isHighRefreshRate': DisplayModeService.isHighRefreshRate,
      'width': DisplayModeService.displayWidth,
      'height': DisplayModeService.displayHeight,
      'supportedModesCount': DisplayModeService.supportedModesCount,
    });
  }

}
