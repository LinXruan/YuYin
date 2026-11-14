part of '../server/agent_automation_server.dart';

/// status 端点处理。
extension AgentStatusHandlers on AgentAutomationServer {
  /// GET /api/status：查询当前应用状态
  Future<void> _handleStatus(HttpRequest request) async {
    final result = _lastResult;
    final Map<String, dynamic>? lastResultJson;
    if (result != null) {
      lastResultJson = {
        'title': result.title,
        'desc': result.desc,
        'isImagePost': result.isImagePost,
        'totalItems': result.items.length,
        'imageCount': result.imageCount,
        'videoCount': result.videoCount,
        'audioCount': result.audioCount,
        'items': _serializeItems(result.items),
      };
    } else {
      lastResultJson = null;
    }

    _sendJson(request, HttpStatus.ok, {
      'app': appName,
      'version': appVersion,
      'busy': busy.value,
      'loggedIn': loggedIn.value,
      'snifferLoggedIn': sniffer?.isUserLoggedIn ?? false,
      'hasParsedResult': result != null,
      'lastInput': _lastRawInput,
      'lastResult': lastResultJson,
      'lastUserHomeResult': _lastUserHomeResult == null
          ? null
          : {
              'secUid': _lastUserHomeResult!.secUid,
              'nickname': _lastUserHomeResult!.nickname,
              'avatarUrl': _lastUserHomeResult!.avatarUrl,
              'hasAvatar': _lastUserHomeResult!.avatarUrl.isNotEmpty,
              'count': _lastUserHomeResult!.count,
              'tabCount': _lastUserHomeResult!.tabCount,
              'worksTotalTag': _lastUserHomeResult!.worksTotalTag,
              'coversCount': _lastUserHomeResult!.coversCount,
              'hasCovers': _lastUserHomeResult!.workCovers.isNotEmpty,
              'titlesCount': _lastUserHomeResult!.titlesCount,
              'hasTitles': _lastUserHomeResult!.workTitles.isNotEmpty,
              'filteredArticleCount': _lastUserHomeResult!.filteredArticleCount,
            },
      'lastUserHomeProfile': _lastUserHomeProfile?.toMap() ??
          _lastUserHomeResult?.profile.toMap(),
      'logsCount': logs.logs.length,
      'downloadSettings': {
        'onlyHighestQualityPerResolution':
            DownloadSettingsStore.onlyHighestQualityPerResolution,
        'isSaveLocationDefault': SaveLocationStore.isAllDefault,
      },
      'display': {
        'activeRefreshRate': DisplayModeService.activeRefreshRate,
        'maxRefreshRate': DisplayModeService.maxRefreshRate,
        'isHighRefreshRate': DisplayModeService.isHighRefreshRate,
      },
    });
  }
}
