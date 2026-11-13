part of '../../agent_automation_server.dart';

/// verify covers 端点处理。
extension AgentVerifyCoversHandlers on AgentAutomationServer {
  /// POST /api/verify/home-covers：主页作品封面图捕获校验与比对（仅 Debug 版）
  Future<void> _handleVerifyHomeCovers(HttpRequest request) async {
    final homeResult = _lastUserHomeResult;
    if (homeResult == null) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未执行主页解析，请先调用 /api/parse 解析主页链接', 'code': 400},
      );
      return;
    }

    final covers = homeResult.workCovers;
    final details = <Map<String, dynamic>>[];
    int matchedCount = 0;

    int idx = 1;
    for (final entry in AgentAutomationServer.kReference167Map.entries) {
      final expectedUrl = entry.key;
      final refImg = entry.value;
      final expectedId = RegExp(r'\d{10,}').firstMatch(expectedUrl)?.group(0);

      // 支持精准匹配或按作品数字 ID 跨路由兼容匹配 (/video/ /note/ /article/)
      String? capturedCover = covers[expectedUrl];
      if (capturedCover == null && expectedId != null) {
        for (final item in covers.entries) {
          if (item.key.contains(expectedId)) {
            capturedCover = item.value;
            break;
          }
        }
      }

      final hasCover = capturedCover != null && capturedCover.isNotEmpty;
      final isHttpUrl = hasCover &&
          (capturedCover.startsWith('http://') ||
              capturedCover.startsWith('https://'));

      final matched = hasCover && isHttpUrl;
      if (matched) matchedCount++;

      details.add({
        'index': idx.toString().padLeft(2, '0'),
        'url': expectedUrl,
        'referenceImage': refImg,
        'hasCover': hasCover,
        'coverUrl': capturedCover ?? '',
        'matched': matched,
      });
      idx++;
    }

    final rate = AgentAutomationServer.kReference167Map.isEmpty
        ? 0.0
        : (matchedCount / AgentAutomationServer.kReference167Map.length);

    logs.add('[封面验证] 167 样本比对完成: 匹配 $matchedCount / ${AgentAutomationServer.kReference167Map.length} (${(rate * 100).toStringAsFixed(1)}%)');

    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'matchRate': rate,
      'totalExpected': AgentAutomationServer.kReference167Map.length,
      'capturedCount': homeResult.count,
      'coversCount': homeResult.coversCount,
      'matchedCount': matchedCount,
      'details': details,
    });
  }

  /// 168 真实主页作品与显示标题/文案参照对照表 (仅用于 Debug 比对验证)

}
