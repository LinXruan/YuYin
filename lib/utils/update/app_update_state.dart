import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/update/app_update_status.dart';
import '../../services/update/model/update_release_info.dart';

/// 应用更新下载的可变状态：状态通知器、Dio、取消令牌与测试目录。
class AppUpdateState {
  static const String updatesSubDir = 'updates';

  final ValueNotifier<AppUpdateStatus> statusNotifier =
      ValueNotifier<AppUpdateStatus>(const AppUpdateStatus());

  Dio? dio;
  CancelToken? cancelToken;
  Directory? testUpdatesDir;

  /// 下载会话号：取消或重下时递增，旧任务据此放弃写状态与删文件
  int sessionId = 0;

  /// 最近一次下载请求，用于失败横幅一键重试
  UpdateReleaseInfo? lastInfo;
}
