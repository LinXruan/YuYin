part of '../server/agent_automation_server.dart';

/// verify profile 端点处理。
extension AgentVerifyProfileHandlers on AgentAutomationServer {
  /// POST /api/verify/home-profile：主页作者头像与昵称捕获校验与比对（仅 Debug 版）
  Future<void> _handleVerifyHomeProfile(HttpRequest request) async {
    final profile = _lastUserHomeProfile ?? _lastUserHomeResult?.profile;
    if (profile == null) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {
          'error': '尚未执行主页解析或未获取到主页信息，请先调用 /api/parse 或 /api/parse-profile 解析主页链接',
          'code': 400,
        },
      );
      return;
    }

    final nickname = profile.nickname.trim();
    final avatarUrl = profile.avatarUrl.trim();
    final secUid = profile.secUid.trim();

    // 在样本表中寻找最匹配的对照项
    Map<String, String>? matchedRef;
    for (final ref in AgentAutomationServer.kReference169Profiles) {
      final refNick = ref['nickname']!;
      final refSecUid = ref['secUid']!;
      if ((secUid.isNotEmpty && secUid.contains(refSecUid)) ||
          (nickname.isNotEmpty && (nickname == refNick || nickname.contains(refNick) || refNick.contains(nickname)))) {
        matchedRef = ref;
        break;
      }
    }

    final bool hasNickname = nickname.isNotEmpty;
    final bool hasAvatar = avatarUrl.isNotEmpty &&
        (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) &&
        avatarUrl.contains('aweme-avatar');

    bool nicknameMatched = false;
    bool avatarUriMatched = false;

    if (matchedRef != null) {
      final expectedNick = matchedRef['nickname']!;
      final expectedUri = matchedRef['avatarUri']!;
      nicknameMatched = nickname.contains(expectedNick) || expectedNick.contains(nickname);
      avatarUriMatched = avatarUrl.contains(expectedUri);
    }

    final bool overallMatched = matchedRef != null
        ? (nicknameMatched && hasAvatar)
        : (hasNickname && hasAvatar);

    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'matched': overallMatched,
      'hasNickname': hasNickname,
      'hasAvatar': hasAvatar,
      'nickname': nickname,
      'avatarUrl': avatarUrl,
      'secUid': secUid,
      'matchedSample': matchedRef?['nickname'],
      'expectedNickname': matchedRef?['nickname'],
      'nicknameMatched': nicknameMatched,
      'avatarUriMatched': avatarUriMatched,
      'expectedAvatarUri': matchedRef?['avatarUri'],
      'avatarFile': matchedRef?['avatarFile'],
      'referenceCount': AgentAutomationServer.kReference169Profiles.length,
    });
  }

}
