part of '../facade/douyin_sniffer.dart';

/// message flow
extension SnifferMessageFlowFlow on DouyinSniffer {
  void _onJavaScriptMessage(JavaScriptMessage message) {
    if (_disposed) return;
    try {
      final data = jsonDecode(message.message);
      if (data is! Map) return;

      // 日志与结果分开接收：结果只处理一次，日志覆盖到任务收尾
      if (data['type'] == 'log') {
        if (!_acceptLogs) return;
        final msg = data['msg']?.toString() ?? '';
        if (msg.isNotEmpty) {
          _log(msg);
          if (msg.contains('正在加载')) {
            _refreshHomeInactivityTimer(_taskId);
          }
        }
        return;
      }

      // hint/result 只在当前任务等待结果期间接收
      if (!_acceptMessages || !_isTaskActive) return;
      if (data['type'] == 'login_state') {
        final remoteLoggedIn = data['loggedIn'] == true;
        final reason = data['reason']?.toString() ?? '';
        _handleLoginStateDetected(remoteLoggedIn, reason, _taskId);
        return;
      }
      if (data['type'] == 'hint') {
        if (data['kind'] == 'video-waiting') {
          final hintId = data['awemeId']?.toString() ?? '';
          if (hintId.isNotEmpty && hintId == _targetAwemeId) {
            if (!_degradedVideoSeen) {
              _degradedVideoSeen = true;
              _log('已确认视频作品，保留主 WebView 等待完整画质');
            }
          }
        }
        return;
      }
      if (data['type'] == 'user_profile_result') {
        final secUid = data['secUid']?.toString() ?? '';
        final nickname = data['nickname']?.toString() ?? '';
        final avatarUrl = data['avatarUrl']?.toString() ?? '';
        if (nickname.isEmpty || avatarUrl.isEmpty) return;
        final profile = UserHomeProfile(
          secUid: secUid,
          nickname: nickname,
          avatarUrl: avatarUrl,
        );
        _finishProfileWithResult(profile, _taskId);
        return;
      }
      if (data['type'] == 'user_home_result') {
        final secUid = data['secUid']?.toString() ?? '';
        final nickname = data['nickname']?.toString() ?? '';
        final avatarUrl = data['avatarUrl']?.toString() ?? '';
        final rawUrls = data['workUrls'];
        final workUrls = <String>[];
        if (rawUrls is List) {
          for (final u in rawUrls) {
            if (u != null) workUrls.add(u.toString());
          }
        }
        final tabCount = int.tryParse(data['tabCount']?.toString() ?? '');
        final rawCovers = data['workCovers'];
        final workCovers = <String, String>{};
        if (rawCovers is Map) {
          for (final entry in rawCovers.entries) {
            final k = entry.key?.toString();
            final v = entry.value?.toString();
            if (k != null && k.isNotEmpty && v != null && v.isNotEmpty) {
              workCovers[k] = v;
            }
          }
        }
        final rawTitles = data['workTitles'];
        final workTitles = <String, String>{};
        if (rawTitles is Map) {
          for (final entry in rawTitles.entries) {
            final k = entry.key?.toString();
            final v = entry.value?.toString();
            if (k != null && k.isNotEmpty && v != null && v.isNotEmpty) {
              workTitles[k] = v;
            }
          }
        }
        // 过滤纯文章作品及其对应的封面/标题映射，避免进入中层保存页
        final articleUrls = workUrls.where(UrlParser.isArticleUrl).toSet();
        if (articleUrls.isNotEmpty) {
          workUrls.removeWhere(articleUrls.contains);
          workCovers.removeWhere((key, _) => articleUrls.contains(key));
          workTitles.removeWhere((key, _) => articleUrls.contains(key));
          _log('已过滤 ${articleUrls.length} 条文章作品链接');
        }

        final homeResult = UserHomeResult(
          secUid: secUid,
          nickname: nickname,
          avatarUrl: avatarUrl,
          workUrls: workUrls,
          workCovers: workCovers,
          workTitles: workTitles,
          tabCount: tabCount,
          filteredArticleCount: articleUrls.length,
        );
        if (_profileCompleter != null && !_profileCompleter!.isCompleted) {
          _finishProfileWithResult(homeResult.profile, _taskId);
        }
        _finishHomeWithResult(homeResult, _taskId);
        return;
      }

      if (data['type'] != 'result') return;
      final items = DouyinSniffer.parseChannelItems(data['items']);
      if (items.isNotEmpty) {
        final desc = data['desc']?.toString();
        final coverUrl = data['coverUrl']?.toString();
        _finishWithItems(
          items,
          data['isImagePost'] == true,
          _taskId,
          desc: desc?.trim().isNotEmpty == true ? desc!.trim() : null,
          coverUrl: coverUrl?.trim().isNotEmpty == true ? coverUrl!.trim() : null,
        );
      }
    } catch (e) {
      _log('解析 Channel 消息失败: $e');
    }
  }
}
