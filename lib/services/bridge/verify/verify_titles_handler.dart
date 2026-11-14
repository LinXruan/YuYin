part of '../server/agent_automation_server.dart';

/// verify titles 端点处理。
extension AgentVerifyTitlesHandlers on AgentAutomationServer {
  /// POST /api/verify/home-titles：主页作品标题/文案捕获校验与比对（仅 Debug 版）
  Future<void> _handleVerifyHomeTitles(HttpRequest request) async {
    final homeResult = _lastUserHomeResult;
    if (homeResult == null) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未执行主页解析，请先调用 /api/parse 解析主页链接', 'code': 400},
      );
      return;
    }

    final titles = homeResult.workTitles;
    final details = <Map<String, dynamic>>[];
    int matchedCount = 0;

    int idx = 1;
    for (final entry in AgentAutomationServer.kReference168TitlesMap.entries) {
      final expectedUrl = entry.key;
      final expectedKeyword = entry.value;
      final expectedId = RegExp(r'\d{10,}').firstMatch(expectedUrl)?.group(0);

      // 支持精准匹配或按作品数字 ID 跨路由兼容匹配 (/video/ /note/ /article/)
      String? capturedTitle = titles[expectedUrl];
      if (capturedTitle == null && expectedId != null) {
        for (final item in titles.entries) {
          if (item.key.contains(expectedId)) {
            capturedTitle = item.value;
            break;
          }
        }
      }

      final hasTitle = capturedTitle != null && capturedTitle.trim().isNotEmpty;
      // 判定匹配：由于卡片文案可能包含省略号，因此检查包含关系或前缀一致
      bool matched = false;
      if (hasTitle) {
        final cleanExpected = expectedKeyword.replaceAll('…', '').replaceAll('...', '').trim();
        final cleanCaptured = capturedTitle.replaceAll('…', '').replaceAll('...', '').trim();
        if (cleanCaptured.contains(cleanExpected) || cleanExpected.contains(cleanCaptured)) {
          matched = true;
        } else {
          final prefixLen = cleanExpected.length < 6 ? cleanExpected.length : 6;
          if (cleanCaptured.startsWith(cleanExpected.substring(0, prefixLen))) {
            matched = true;
          }
        }
      }

      if (matched) matchedCount++;

      final summary = capturedTitle == null
          ? ''
          : (capturedTitle.length > 20 ? '${capturedTitle.substring(0, 20)}...' : capturedTitle);

      details.add({
        'index': idx.toString().padLeft(2, '0'),
        'url': expectedUrl,
        'expectedTitle': expectedKeyword,
        'hasTitle': hasTitle,
        'title': capturedTitle ?? '',
        'titleSummary': summary,
        'matched': matched,
      });
      idx++;
    }

    final rate = AgentAutomationServer.kReference168TitlesMap.isEmpty
        ? 0.0
        : (matchedCount / AgentAutomationServer.kReference168TitlesMap.length);

    logs.add('[标题验证] 168 样本比对完成: 匹配 $matchedCount / ${AgentAutomationServer.kReference168TitlesMap.length} (${(rate * 100).toStringAsFixed(1)}%)');

    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'matchRate': rate,
      'totalExpected': AgentAutomationServer.kReference168TitlesMap.length,
      'capturedCount': homeResult.count,
      'titlesCount': homeResult.titlesCount,
      'matchedCount': matchedCount,
      'details': details,
    });
  }

}
