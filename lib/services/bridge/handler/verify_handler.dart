import 'dart:io';

import '../server/agent_automation_server.dart';

/// 校验端点：主页封面、标题与作者资料与样表比对（仅 Debug 版）。
class VerifyHandler {
  VerifyHandler(this.server);

  final AgentAutomationServer server;

  /// POST /api/verify/home-covers
  Future<void> handleHomeCovers(HttpRequest request) async {
    final homeResult = server.lastUserHomeResult;
    if (homeResult == null) {
      server.sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未执行主页解析，请先调用 /api/parse 解析主页链接', 'code': 400},
      );
      return;
    }

    final covers = homeResult.workCovers;
    final details = <Map<String, dynamic>>[];
    var matchedCount = 0;

    var idx = 1;
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

    final total = AgentAutomationServer.kReference167Map.length;
    final rate = total == 0 ? 0.0 : matchedCount / total;
    server.logs.add(
      '167 样本比对完成: 匹配 $matchedCount / $total '
      '(${(rate * 100).toStringAsFixed(1)}%)',
    );

    server.sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'matchRate': rate,
      'totalExpected': total,
      'capturedCount': homeResult.count,
      'coversCount': homeResult.coversCount,
      'matchedCount': matchedCount,
      'details': details,
    });
  }

  /// POST /api/verify/home-titles
  Future<void> handleHomeTitles(HttpRequest request) async {
    final homeResult = server.lastUserHomeResult;
    if (homeResult == null) {
      server.sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未执行主页解析，请先调用 /api/parse 解析主页链接', 'code': 400},
      );
      return;
    }

    final titles = homeResult.workTitles;
    final details = <Map<String, dynamic>>[];
    var matchedCount = 0;

    var idx = 1;
    for (final entry in AgentAutomationServer.kReference168TitlesMap.entries) {
      final expectedUrl = entry.key;
      final expectedKeyword = entry.value;
      final expectedId = RegExp(r'\d{10,}').firstMatch(expectedUrl)?.group(0);

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
      var matched = false;
      if (hasTitle) {
        final cleanExpected =
            expectedKeyword.replaceAll('…', '').replaceAll('...', '').trim();
        final cleanCaptured =
            capturedTitle.replaceAll('…', '').replaceAll('...', '').trim();
        if (cleanCaptured.contains(cleanExpected) ||
            cleanExpected.contains(cleanCaptured)) {
          matched = true;
        } else {
          final prefixLen =
              cleanExpected.length < 6 ? cleanExpected.length : 6;
          if (cleanCaptured.startsWith(cleanExpected.substring(0, prefixLen))) {
            matched = true;
          }
        }
      }

      if (matched) matchedCount++;
      final summary = capturedTitle == null
          ? ''
          : (capturedTitle.length > 20
              ? '${capturedTitle.substring(0, 20)}...'
              : capturedTitle);

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

    final total = AgentAutomationServer.kReference168TitlesMap.length;
    final rate = total == 0 ? 0.0 : matchedCount / total;
    server.logs.add(
      '168 样本比对完成: 匹配 $matchedCount / $total '
      '(${(rate * 100).toStringAsFixed(1)}%)',
    );

    server.sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'matchRate': rate,
      'totalExpected': total,
      'capturedCount': homeResult.count,
      'titlesCount': homeResult.titlesCount,
      'matchedCount': matchedCount,
      'details': details,
    });
  }

  /// POST /api/verify/home-profile
  Future<void> handleHomeProfile(HttpRequest request) async {
    final profile = server.lastUserHomeProfile ?? server.lastUserHomeResult?.profile;
    if (profile == null) {
      server.sendJson(
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

    Map<String, String>? matchedRef;
    for (final ref in AgentAutomationServer.kReference169Profiles) {
      final refNick = ref['nickname']!;
      final refSecUid = ref['secUid']!;
      if ((secUid.isNotEmpty && secUid.contains(refSecUid)) ||
          (nickname.isNotEmpty &&
              (nickname == refNick ||
                  nickname.contains(refNick) ||
                  refNick.contains(nickname)))) {
        matchedRef = ref;
        break;
      }
    }

    final hasNickname = nickname.isNotEmpty;
    final hasAvatar = avatarUrl.isNotEmpty &&
        (avatarUrl.startsWith('http://') || avatarUrl.startsWith('https://')) &&
        avatarUrl.contains('aweme-avatar');

    var nicknameMatched = false;
    var avatarUriMatched = false;
    if (matchedRef != null) {
      final expectedNick = matchedRef['nickname']!;
      final expectedUri = matchedRef['avatarUri']!;
      nicknameMatched =
          nickname.contains(expectedNick) || expectedNick.contains(nickname);
      avatarUriMatched = avatarUrl.contains(expectedUri);
    }

    final overallMatched = matchedRef != null
        ? (nicknameMatched && hasAvatar)
        : (hasNickname && hasAvatar);

    server.sendJson(request, HttpStatus.ok, {
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
