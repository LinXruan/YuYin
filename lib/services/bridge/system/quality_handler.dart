part of '../../agent_automation_server.dart';

/// quality 端点处理。
extension AgentQualityHandlers on AgentAutomationServer {
  /// POST /api/settings/quality：切换“仅显示同分辨率下最高画质”开关
  Future<void> _handleSetQualitySetting(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final enabled = body['onlyHighestQualityPerResolution'];
    if (enabled is! bool) {
      _sendJson(
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
    _sendJson(request, HttpStatus.ok, {
      'success': true,
      'onlyHighestQualityPerResolution':
          DownloadSettingsStore.onlyHighestQualityPerResolution,
    });
  }

}
