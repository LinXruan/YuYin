import 'dart:convert';

import '../../../models/user_home/user_home_profile.dart';
import '../../../models/user_home/user_home_result.dart';
import '../../../utils/url_parser.dart';
import '../channel/sniffer_channel_parser.dart';
import '../common/log_message_policy.dart';
import 'login_message_handler.dart';
import 'sniffer_message_host.dart';

/// 捕获脚本 Channel 消息路由：log / hint / result / home / profile / login。
class SnifferMessageRouter {
  SnifferMessageRouter(this.host) : _login = LoginMessageHandler(host);

  final SnifferMessageHost host;
  final LoginMessageHandler _login;

  void onMessage(String raw) {
    if (host.isDisposed) return;
    try {
      final data = jsonDecode(raw);
      if (data is! Map) return;

      // 只接收当前任务文档的消息；旧文档的迟到消息一律丢弃
      if (data['task'] != host.taskNonce) return;

      // 日志与结果分开接收：结果只处理一次，日志覆盖到任务收尾
      if (data['type'] == 'log') {
        _handleLog(data);
        return;
      }

      // hint/result 只在当前任务等待结果期间接收
      if (!host.session.acceptMessages || !host.isTaskActive) return;
      switch (data['type']) {
        case 'login_state':
          _login.handle(
            data['loggedIn'] == true,
            data['reason']?.toString() ?? '',
            host.session.taskId,
          );
        case 'hint':
          _handleHint(data);
        case 'user_profile_result':
          _handleProfile(data);
        case 'user_home_result':
          _handleHome(data);
        case 'result':
          _handleResult(data);
      }
    } catch (e) {
      host.logDiagnostic('解析 Channel 消息失败: $e');
    }
  }

  void _handleLog(Map data) {
    if (!host.session.acceptLogs) return;
    final msg = data['msg']?.toString() ?? '';
    if (msg.isEmpty) return;
    if (LogMessagePolicy.classify(msg) == SnifferLogKind.homeProgress) {
      // 主页进度日志即视为滚动存活信号，刷新失活定时器
      host.reportUserLog(LogMessagePolicy.formatHomeProgress(msg));
      host.refreshHomeInactivity(host.session.taskId);
    } else {
      host.logDiagnostic(msg);
    }
  }

  void _handleHint(Map data) {
    if (data['kind'] != 'video-waiting') return;
    final hintId = data['awemeId']?.toString() ?? '';
    if (hintId.isNotEmpty && hintId == host.session.targetAwemeId) {
      host.session.degradedVideoSeen = true;
    }
  }

  void _handleProfile(Map data) {
    final nickname = data['nickname']?.toString() ?? '';
    final avatarUrl = data['avatarUrl']?.toString() ?? '';
    if (nickname.isEmpty || avatarUrl.isEmpty) return;
    host.finishProfile(
      UserHomeProfile(
        secUid: data['secUid']?.toString() ?? '',
        nickname: nickname,
        avatarUrl: avatarUrl,
      ),
      host.session.taskId,
    );
  }

  void _handleHome(Map data) {
    final workUrls = <String>[];
    final rawUrls = data['workUrls'];
    if (rawUrls is List) {
      for (final url in rawUrls) {
        if (url != null) workUrls.add(url.toString());
      }
    }

    final workCovers = _stringMap(data['workCovers']);
    final workTitles = _stringMap(data['workTitles']);

    // 过滤纯文章作品及其对应的封面/标题映射，避免进入中层保存页
    final articleUrls = workUrls.where(UrlParser.isArticleUrl).toSet();
    if (articleUrls.isNotEmpty) {
      workUrls.removeWhere(articleUrls.contains);
      workCovers.removeWhere((key, _) => articleUrls.contains(key));
      workTitles.removeWhere((key, _) => articleUrls.contains(key));
      host.reportUserLog('已过滤 ${articleUrls.length} 条文章作品链接');
    }

    final home = UserHomeResult(
      secUid: data['secUid']?.toString() ?? '',
      nickname: data['nickname']?.toString() ?? '',
      avatarUrl: data['avatarUrl']?.toString() ?? '',
      workUrls: workUrls,
      workCovers: workCovers,
      workTitles: workTitles,
      tabCount: int.tryParse(data['tabCount']?.toString() ?? ''),
      filteredArticleCount: articleUrls.length,
      partial: data['partial'] == true,
    );
    final completer = host.session.profileCompleter;
    if (completer != null && !completer.isCompleted) {
      host.finishProfile(home.profile, host.session.taskId);
    }
    host.finishHome(home, host.session.taskId);
  }

  Future<void> _handleResult(Map data) {
    final items = SnifferChannelParser.parseChannelItems(data['items']);
    if (items.isEmpty) return Future<void>.value();
    final desc = data['desc']?.toString().trim();
    final coverUrl = data['coverUrl']?.toString().trim();
    final rawAwemeId = data['awemeId']?.toString().trim();
    return host.finishResultItems(
      items,
      data['isImagePost'] == true,
      host.session.taskId,
      desc: desc?.isEmpty == true ? null : desc,
      coverUrl: coverUrl?.isEmpty == true ? null : coverUrl,
      // 空串归一化为 null，避免多个短链作品被同一个空 id 误去重
      awemeId: (rawAwemeId == null || rawAwemeId.isEmpty) ? null : rawAwemeId,
    );
  }

  Map<String, String> _stringMap(Object? raw) {
    final result = <String, String>{};
    if (raw is! Map) return result;
    for (final entry in raw.entries) {
      final key = entry.key?.toString();
      final value = entry.value?.toString();
      if (key != null && key.isNotEmpty && value != null && value.isNotEmpty) {
        result[key] = value;
      }
    }
    return result;
  }
}
