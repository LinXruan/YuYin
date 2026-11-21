import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../../../models/parse/parse_status.dart';
import '../../../../services/batch_work/work_batch_saver.dart';
import '../../../../services/media/video_downloader.dart';
import '../../../../services/sniffer/facade/douyin_sniffer.dart';
import '../../../../utils/debug/log_controller.dart';
import 'parse_save_coordinator.dart';

/// 解析流程上下文：向各个 Coordinator 提供页面级依赖与状态控制
class ParseFlowContext {
  const ParseFlowContext({
    required this.context,
    required this.sniffer,
    required this.downloader,
    required this.logs,
    required this.busy,
    required this.loggedIn,
    required this.onRequestParseTab,
    required this.isParsing,
    required this.setParsing,
    required this.getDownloadCancelToken,
    required this.setDownloadCancelToken,
    required this.updateBatchSaveProgress,
    required this.updateBatchProgress,
    required this.saveCoordinator,
    required this.workBatchSaver,
    required this.refresh,
    required this.statusNotifier,
  });

  final BuildContext context;
  final DouyinSniffer sniffer;
  final VideoDownloader downloader;
  final LogController logs;
  final ValueNotifier<bool> busy;
  final ValueNotifier<bool> loggedIn;
  final VoidCallback onRequestParseTab;
  final bool Function() isParsing;
  final void Function(bool) setParsing;
  final CancelToken? Function() getDownloadCancelToken;
  final void Function(CancelToken?) setDownloadCancelToken;
  final void Function(int current, int total, String message)
      updateBatchSaveProgress;
  final void Function(int current, int total, double itemProgress)
      updateBatchProgress;
  final ParseSaveCoordinator saveCoordinator;
  final WorkBatchSaver workBatchSaver;
  final VoidCallback refresh;
  final ValueNotifier<ParseStatus> statusNotifier;

  void setStatus(ParseStatus status) => statusNotifier.value = status;

  bool get mounted => context.mounted;
}
