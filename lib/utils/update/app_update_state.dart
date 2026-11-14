import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../models/update/app_update_status.dart';

/// 应用更新下载的可变状态：状态通知器、Dio、取消令牌与测试目录。
class AppUpdateState {
  static const String updatesSubDir = 'updates';

  final ValueNotifier<AppUpdateStatus> statusNotifier =
      ValueNotifier<AppUpdateStatus>(const AppUpdateStatus());

  Dio? dio;
  CancelToken? cancelToken;
  Directory? testUpdatesDir;
}
