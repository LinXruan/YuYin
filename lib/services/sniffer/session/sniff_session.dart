import 'dart:async';

import '../../../models/single_work/single_work_result.dart';
import '../../../models/url/douyin_link_kind.dart';
import '../../../models/user_home/user_home_profile.dart';
import '../../../models/user_home/user_home_result.dart';
import '../../share/model/share_models.dart';

/// 单次捕获任务的共享状态。
///
/// 只承载可变数据，不做判断与调度；任务开始时由门面重置，任务结束后清空。
class SniffSession {
  Completer<SniffResult>? completer;
  Completer<UserHomeResult>? homeCompleter;
  Completer<UserHomeProfile>? profileCompleter;

  Timer? timeoutTimer;
  Timer? injectTimer;
  Timer? unloadTimer;
  Timer? imageGraceTimer;
  Timer? webviewFallbackDelay;
  Timer? webviewFallbackTimer;
  Timer? lateFallbackTimer;

  /// 任务开始前重置页面的提交信号
  Completer<void>? pageReset;

  /// 结果/提示只接收一次；日志只在本任务页面存续期间接收
  bool acceptMessages = false;
  bool acceptLogs = false;

  /// 任务序号：异步回调返回时用它丢弃旧任务结果
  int taskId = 0;

  /// 当前任务标识：脚本与回传消息共用，旧文档的迟到消息据此丢弃
  String get taskNonce => 't$taskId';

  String? lastPageUrl;
  String? retiredAwemeId;
  bool taskPageStarted = false;
  String? targetAwemeId;

  bool shareFallbackStarted = false;
  DouyinShareResult? shareVideoFallback;
  DouyinShareResult? pendingImageResult;
  bool shareFallbackFailed = false;

  bool webviewShareFallback = false;
  DouyinWorkPage workPageKind = DouyinWorkPage.unknown;
  bool degradedVideoSeen = false;

  String? sourceUrl;
  String? awemePageUrl;
  DateTime taskStartedAt = DateTime.now();

  String? lastWebResourceError;
  bool loggedWebResourceError = false;
  bool loggedNonWebPage = false;
  bool loggedInjectFailure = false;
  bool loggedCaptchaFailure = false;
}
