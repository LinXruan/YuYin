part of '../server/agent_automation_server.dart';

/// status 端点处理。
extension AgentStatusHandlers on AgentAutomationServer {
  /// GET /api/status：查询当前应用状态
  Future<void> _handleStatus(HttpRequest request) async {
    final result = lastResult;
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
        'items': serializeItems(result.items),
      };
    } else {
      lastResultJson = null;
    }

    sendJson(request, HttpStatus.ok, {
      'app': appName,
      'version': appVersion,
      'busy': busy.value,
      'loggedIn': loggedIn.value,
      'snifferLoggedIn': sniffer?.isUserLoggedIn ?? false,
      'hasParsedResult': result != null,
      'lastInput': lastRawInput,
      'lastResult': lastResultJson,
      'lastUserHomeResult': lastUserHomeResult == null
          ? null
          : {
              'secUid': lastUserHomeResult!.secUid,
              'nickname': lastUserHomeResult!.nickname,
              'avatarUrl': lastUserHomeResult!.avatarUrl,
              'hasAvatar': lastUserHomeResult!.avatarUrl.isNotEmpty,
              'count': lastUserHomeResult!.count,
              'tabCount': lastUserHomeResult!.tabCount,
              'worksTotalTag': lastUserHomeResult!.worksTotalTag,
              'coversCount': lastUserHomeResult!.coversCount,
              'hasCovers': lastUserHomeResult!.workCovers.isNotEmpty,
              'titlesCount': lastUserHomeResult!.titlesCount,
              'hasTitles': lastUserHomeResult!.workTitles.isNotEmpty,
              'filteredArticleCount': lastUserHomeResult!.filteredArticleCount,
            },
      'lastUserHomeProfile': lastUserHomeProfile?.toMap() ??
          lastUserHomeResult?.profile.toMap(),
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
