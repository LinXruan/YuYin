part of '../../douyin_sniffer.dart';

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

  /// 处理从当前页面捕获到的远端登录状态：未登录时立即中断多画质等待并自适应降级

  void _handleLoginStateDetected(
    bool remoteLoggedIn,
    String reason,
    int taskId,
  ) {
    if (taskId != _taskId || !_isTaskActive) return;

    if (!remoteLoggedIn) {
      if (kDebugMode) {
        _log('检测到远端登录状态: 未登录 (原因: $reason)');
      }
      final wasLoggedIn = _isLoggedIn;
      _isLoggedIn = false;

      if (wasLoggedIn) {
        onLoginStateDetected?.call(false);
        // 若之前分享页兜底已经拿到了无水印视频（此前被暂存等待完整画质），立即结束解析！
        final cached = _shareVideoFallback;
        if (cached != null && cached.items.isNotEmpty) {
          if (kDebugMode) {
            _log('远端未登录：立即使用已就绪的分享页视频极速完成解析');
          } else {
            _log('分享页已获取无水印视频，完成解析');
          }
          unawaited(
            _finishWithItems(
              cached.items,
              false,
              taskId,
              title: cached.title,
              desc: cached.desc,
              coverUrl: cached.coverUrl,
            ),
          );
        }
      }
    } else {
      if (kDebugMode) {
        _log('检测到远端登录状态: 已登录 (原因: $reason)');
      }
      _isLoggedIn = true;
      onLoginStateDetected?.call(true);
    }
  }

  /// 解析 Channel 中的 login_state 消息（纯函数，便于测试）
  Future<void> _finishWithItems(
    List<MediaItem> items,
    bool isImagePost,
    int taskId, {
    String? title,
    String? desc,
    String? coverUrl,
  }) async {
    if (taskId != _taskId) return;
    final completer = _completer;
    if (completer == null || completer.isCompleted) return;

    // 结果只处理一次；日志继续接收，等待 Cookie 读取期间的 JS 收尾日志
    _acceptMessages = false;
    _stopTimers();

    var cookie = '';
    try {
      cookie = _jsResultToString(
        await _controller
            .runJavaScriptReturningResult('document.cookie')
            .timeout(const Duration(seconds: 3)),
      );
    } catch (e) {
      _log('读取 Cookie 失败: $e');
    }

    // 等待期间可能已开始新任务：此时不能清状态或关闭新任务的日志
    if (taskId != _taskId ||
        !identical(_completer, completer) ||
        completer.isCompleted) {
      return;
    }

    _acceptLogs = false;
    // 主 WebView 结果缺失封面时，使用并行分享页兜底结果中的封面
    var effectiveCover = coverUrl?.trim() ?? '';
    if (effectiveCover.isEmpty) {
      final fallbackCover = _shareVideoFallback?.coverUrl?.trim() ?? '';
      if (fallbackCover.isNotEmpty) {
        effectiveCover = fallbackCover;
        if (kDebugMode) {
          _log('主结果封面缺失，已使用分享页封面兜底');
        }
      }
    }
    final result = SniffResult(
      items: items,
      cookie: cookie,
      isImagePost: isImagePost,
      title: title,
      desc: desc,
      coverUrl: effectiveCover.isEmpty ? null : effectiveCover,
    );
    final audioPart =
        result.audioCount > 0 ? '、${result.audioCount} 首配乐音频' : '';
    final summary = isImagePost
        ? '解析成功：共发现 ${result.imageCount} 张图片、${result.videoCount} 个视频$audioPart'
        : '解析成功：共发现 ${result.items.length} 个清晰度档位';
    _log(summary);
    if (desc != null && desc.isNotEmpty) {
      final shortDesc = desc.length > 30 ? '${desc.substring(0, 30)}...' : desc;
      _log('作品文案: $shortDesc');
    }
    completer.complete(result);
    if (identical(_completer, completer)) _completer = null;

    // 解析成功后立即卸载当前网页，释放 DOM、播放器及后台脚本占用的内存
    unawaited(
      _controller.loadRequest(Uri.parse('about:blank')).catchError((Object error) {
        debugPrint('卸载网页释放内存失败: $error');
      }),
    );
  }

  /// 检测验证码中间页，命中后提前结束等待

  String _jsResultToString(Object result) {
    final text = result.toString();
    if (text.startsWith('"') && text.endsWith('"')) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is String) return decoded;
      } catch (e) {
        _log('解析 JS 字符串失败: $e');
      }
    }
    return text == 'null' ? '' : text;
  }

  /// 取消超时、轮询注入、WebView 兜底定时器，并取消分享页请求

  void _finishWithError(Object error, {int? taskId}) {
    // 过期任务不能停掉新任务的定时器或分享页请求
    if (taskId != null && taskId != _taskId) return;
    _acceptMessages = false;
    _acceptLogs = false;
    final completer = _completer;
    _completer = null;
    _stopTimers();
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }
}
