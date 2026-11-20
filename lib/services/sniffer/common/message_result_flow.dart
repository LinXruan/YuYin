part of '../facade/douyin_sniffer.dart';

/// 结果消息收尾：完成、字符串解析与错误。
extension SnifferMessageResultFlow on DouyinSniffer {
  /// 解析 Channel 中的 login_state 消息（纯函数，便于测试）
  Future<void> _finishWithItems(
    List<MediaItem> items,
    bool isImagePost,
    int taskId, {
    String? title,
    String? desc,
    String? coverUrl,
    String? awemeId,
  }) async {
    if (taskId != _session.taskId) return;
    final completer = _session.completer;
    if (completer == null || completer.isCompleted) return;

    // 结果只处理一次；日志继续接收，等待 Cookie 读取期间的 JS 收尾日志
    _session.acceptMessages = false;
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
    if (taskId != _session.taskId ||
        !identical(_session.completer, completer) ||
        completer.isCompleted) {
      return;
    }

    _session.acceptLogs = false;
    // 主 WebView 结果缺失封面时，使用并行分享页兜底结果中的封面
    var effectiveCover = coverUrl?.trim() ?? '';
    if (effectiveCover.isEmpty) {
      final fallbackCover = _session.shareVideoFallback?.coverUrl?.trim() ?? '';
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
      awemeId: awemeId,
    );
    _session.retiredAwemeId =
        awemeId ?? UrlParser.extractAwemeId(_session.lastPageUrl ?? '');
    final audioPart =
        result.audioCount > 0 ? '、${result.audioCount} 首配乐音频' : '';
    final summary = isImagePost
        ? '解析成功：共发现 ${result.imageCount} 张图片、${result.videoCount} 个视频$audioPart'
        : '解析成功：共发现 ${result.items.length} 个清晰度档位';
    _report(summary);
    completer.complete(result);
    if (identical(_session.completer, completer)) _session.completer = null;

    // 无新任务时延迟卸载；批量下一条会先取消
    _schedulePageUnload();
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
    if (taskId != null && taskId != _session.taskId) return;
    _session.acceptMessages = false;
    _session.acceptLogs = false;
    final completer = _session.completer;
    _session.completer = null;
    _stopTimers();
    if (completer == null || completer.isCompleted) return;
    completer.completeError(error);
  }
}
