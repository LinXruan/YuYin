part of '../server/agent_automation_server.dart';

/// parse profile 端点处理。
extension AgentParseProfileHandlers on AgentAutomationServer {
  /// POST /api/parse-profile：快速提取主页作者信息（昵称与头像，不等待作品滚动）
  Future<void> _handleParseProfile(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final text = body['text']?.toString() ?? '';
    if (text.isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '缺少 text 参数（分享文本或链接）', 'code': 400},
      );
      return;
    }

    final url = UrlParser.extractDouyinUrl(text) ?? text.trim();
    if (url.isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '未提取到有效 URL', 'code': 400},
      );
      return;
    }

    if (!UrlParser.isUserHomeUrl(url)) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '给定的链接不是抖音用户主页链接: $url', 'code': 400},
      );
      return;
    }

    if (!loggedIn.value) {
      logs.reset('正在提取短链...');
      logs.add('请登录再进行主页链接解析');
      _sendJson(
        request,
        HttpStatus.forbidden,
        {'error': '请登录再进行主页链接解析', 'code': 403, 'isUserHome': true},
      );
      return;
    }

    busy.value = true;
    logs.reset('正在提取短链...');
    logs.add('正在捕获主页作者信息（头像与昵称）...');
    try {
      final currentSniffer = sniffer;
      if (currentSniffer == null) {
        throw StateError('捕获服务未初始化');
      }
      final profile = await currentSniffer.sniffUserProfile(url);
      _lastUserHomeProfile = profile;
      _lastRawInput = text;
      _lastParsedUrl = url;
      final author = profile.nickname.isNotEmpty ? profile.nickname : '未知作者';
      final hasAvatar = profile.avatarUrl.isNotEmpty;
      logs.add('[主页] 成功捕获作者【$author】基础资料（${hasAvatar ? "已获取头像" : "未获取头像"}）');
      _sendJson(request, HttpStatus.ok, {
        'status': 'ok',
        'type': 'user_profile',
        'profile': profile.toMap(),
        'logs': logs.logs,
      });
    } catch (e) {
      logs.add('主页作者信息捕获失败: $e');
      _sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': '$e', 'code': 500},
      );
    } finally {
      busy.value = false;
    }
  }

}
