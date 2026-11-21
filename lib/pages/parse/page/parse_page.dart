import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/parse/parse_status.dart';
import '../../../services/batch_work/work_batch_saver.dart';
import '../../../services/media/video_downloader.dart';
import '../../../services/sniffer/facade/douyin_sniffer.dart';
import '../../../utils/debug/log_controller.dart';
import '../../../utils/network_detector.dart';
import '../../../utils/url/batch_input_parser.dart';
import '../flow/common/parse_flow_context.dart';
import '../flow/common/parse_save_coordinator.dart';
import '../flow/home/home_parse_coordinator.dart';
import '../flow/multi/multi_parse_coordinator.dart';
import '../flow/single/single_parse_coordinator.dart';
import '../widget/frame/parse_frame.dart';

/// 解析页：粘贴链接 -> 捕获 -> 选择画质/图片 -> 下载
class ParsePage extends StatefulWidget {
  const ParsePage({
    super.key,
    required this.sniffer,
    required this.downloader,
    required this.logs,
    required this.busy,
    required this.loggedIn,
    required this.onRequestParseTab,
    this.onTapAccount,
    this.externalUrlNotifier,
  });

  final DouyinSniffer sniffer;
  final VideoDownloader downloader;
  final LogController logs;
  final ValueNotifier<bool> busy;
  final ValueNotifier<bool> loggedIn;
  final VoidCallback onRequestParseTab;
  final VoidCallback? onTapAccount;
  final ValueNotifier<String?>? externalUrlNotifier;

  @override
  State<ParsePage> createState() => _ParsePageState();
}

class _ParsePageState extends State<ParsePage>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _inputScrollController = ScrollController();
  final ValueNotifier<ParseStatus> _statusNotifier =
      ValueNotifier(const ParseStatus.idle());
  final ValueNotifier<double?> _downloadProgress = ValueNotifier(null);
  final ValueNotifier<CancelToken?> _downloadToken = ValueNotifier(null);
  bool _downloadTokenDisposed = false;
  String _lastProgressKey = '';
  bool _isParsing = false;

  /// 下载/保存中的取消令牌：由 notifier 承载，变化即触发按钮重建
  CancelToken? get _downloadCancelToken => _downloadToken.value;

  set _downloadCancelToken(CancelToken? token) {
    if (_downloadTokenDisposed) return;
    _downloadToken.value = token;
  }

  /// 批量作品保存器（下载器与嗅探器均实现对应代理）
  WorkBatchSaver get _workBatchSaver =>
      WorkBatchSaver(downloader: widget.downloader);

  ParseSaveCoordinator get _saveCoordinator =>
      ParseSaveCoordinator(sniffer: widget.sniffer, logs: widget.logs);

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.externalUrlNotifier?.addListener(_onExternalUrlChanged);
    final initialUrl = widget.externalUrlNotifier?.value;
    if (initialUrl != null && initialUrl.isNotEmpty) {
      _applyExternalUrl(initialUrl);
    }
  }

  @override
  void didUpdateWidget(covariant ParsePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.externalUrlNotifier != widget.externalUrlNotifier) {
      oldWidget.externalUrlNotifier?.removeListener(_onExternalUrlChanged);
      widget.externalUrlNotifier?.addListener(_onExternalUrlChanged);
      final url = widget.externalUrlNotifier?.value;
      if (url != null && url.isNotEmpty) {
        _applyExternalUrl(url);
      }
    }
  }

  void _onExternalUrlChanged() {
    final url = widget.externalUrlNotifier?.value;
    if (url != null && url.isNotEmpty) {
      _applyExternalUrl(url);
    }
  }

  void _applyExternalUrl(String url) {
    if (!mounted) return;
    _inputController.text = url;
    _inputController.selection = TextSelection.fromPosition(
      TextPosition(offset: _inputController.text.length),
    );
    if (_inputScrollController.hasClients) {
      _inputScrollController.jumpTo(0.0);
    }
    if (!_isParsing && _downloadCancelToken == null) {
      _startParse();
    }
  }

  void _cancelParse() {
    if (!_isParsing) return;
    _isParsing = false;
    _statusNotifier.value = const ParseStatus.idle(message: '已取消解析');
    if (mounted) setState(() {});
    widget.sniffer.cancelActiveTask();
  }

  void _cancelDownload() {
    final token = _downloadCancelToken;
    if (token == null) return;
    token.cancel('用户取消保存');
    _statusNotifier.value = const ParseStatus.idle(message: '已取消保存');
    widget.sniffer.cancelActiveTask();
    if (mounted) setState(() {});
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      _inputController.text = data!.text!;
      if (_inputScrollController.hasClients) {
        _inputScrollController.jumpTo(0.0);
      }
    }
  }

  void _updateBatchSaveProgress(int current, int total, String message) {
    if (!mounted) return;
    final prefix = message.startsWith('正在准备') ? '正在准备' : '正在保存';
    widget.logs.upsertLast(prefix, message);
    _statusNotifier.value = ParseStatus.saving(message: message);
    final overall = total == 0 ? 0.0 : current / total;
    _downloadProgress.value = overall.clamp(0.0, 1.0).toDouble();
  }

  void _updateBatchProgress(int current, int total, double itemProgress) {
    final percent = (itemProgress * 100).round();
    final key = '$current/$total/$percent';
    if (!mounted || key == _lastProgressKey) return;
    _lastProgressKey = key;

    final overall = total == 0 ? 0.0 : ((current - 1) + itemProgress) / total;
    final msg = '正在下载第 $current/$total 个资源（$percent%）...';
    widget.logs.upsertLast('正在下载第', msg);
    _statusNotifier.value = ParseStatus.saving(message: msg);
    _downloadProgress.value = overall.clamp(0.0, 1.0).toDouble();
  }

  ParseFlowContext _createFlowContext() => ParseFlowContext(
        context: context,
        sniffer: widget.sniffer,
        downloader: widget.downloader,
        logs: widget.logs,
        busy: widget.busy,
        loggedIn: widget.loggedIn,
        onRequestParseTab: widget.onRequestParseTab,
        isParsing: () => _isParsing,
        setParsing: (val) => _isParsing = val,
        getDownloadCancelToken: () => _downloadCancelToken,
        setDownloadCancelToken: (token) => _downloadCancelToken = token,
        updateBatchSaveProgress: _updateBatchSaveProgress,
        updateBatchProgress: _updateBatchProgress,
        saveCoordinator: _saveCoordinator,
        workBatchSaver: _workBatchSaver,
        statusNotifier: _statusNotifier,
        refresh: () {
          if (mounted) setState(() {});
        },
      );

  void _retryFailed(List<String> failedUrls) {
    if (failedUrls.isEmpty || widget.busy.value) return;
    _applyExternalUrl(failedUrls.join('\n'));
    _startParse();
  }

  Future<void> _startParse() async {
    if (widget.busy.value) return;
    FocusScope.of(context).unfocus();

    final hasNet = await NetworkDetector.hasInternetConnection();
    if (!mounted) return;
    if (!hasNet) {
      widget.logs.reset('网络未连接，无法解析');
      _statusNotifier.value = const ParseStatus.failed(message: '网络未连接，无法解析');
      NetworkDetector.showOfflineSnackbar(context);
      return;
    }

    widget.logs.reset('正在提取短链...');
    _statusNotifier.value = const ParseStatus.parsing(message: '正在提取短链...');
    _downloadProgress.value = null;
    _lastProgressKey = '';
    widget.busy.value = true;
    _isParsing = true;
    if (mounted) setState(() {});

    final batch = DouyinBatchInputParser.parseBatchInput(_inputController.text);
    if (batch.kind == ParsedBatchKind.empty) {
      widget.logs.add('未识别到有效的抖音链接，请检查粘贴内容');
      _statusNotifier.value =
          const ParseStatus.failed(message: '未识别到有效的抖音链接，请检查粘贴内容');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) setState(() {});
      return;
    }

    if (batch.filteredArticleCount > 0) {
      widget.logs.add('已自动过滤 ${batch.filteredArticleCount} 条文章作品链接');
    }

    if (batch.kind == ParsedBatchKind.articlesOnly) {
      widget.logs.add('未识别到可下载的视频/图文作品（文章作品暂不支持）');
      _statusNotifier.value =
          const ParseStatus.failed(message: '未识别到可下载的视频/图文作品（文章作品暂不支持）');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) setState(() {});
      return;
    }

    if (batch.kind == ParsedBatchKind.mixed) {
      widget.logs.add('检测到同时包含主页链接和作品链接，请分开粘贴解析');
      _statusNotifier.value =
          const ParseStatus.failed(message: '检测到同时包含主页链接和作品链接，请分开粘贴解析');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) setState(() {});
      return;
    }

    final flowContext = _createFlowContext();
    if (batch.kind == ParsedBatchKind.multiWork) {
      await MultiParseCoordinator(flowContext).parseMultiWorks(
        batch.workUrls,
        _inputController.text,
      );
      return;
    }

    if (batch.kind == ParsedBatchKind.userHomes) {
      await HomeParseCoordinator(flowContext).parseUserHomes(batch.homeUrls);
      return;
    }

    await SingleParseCoordinator(flowContext).parseSingleWork(
      batch.workUrls.first,
      _inputController.text,
    );
  }

  @override
  void dispose() {
    widget.externalUrlNotifier?.removeListener(_onExternalUrlChanged);
    if (_isParsing) {
      widget.sniffer.cancelActiveTask();
    }
    _downloadCancelToken?.cancel('页面已销毁');
    _downloadTokenDisposed = true;
    _downloadToken.dispose();
    _downloadProgress.dispose();
    _statusNotifier.dispose();
    _inputController.dispose();
    _inputScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ParseFrame(
      inputController: _inputController,
      inputScrollController: _inputScrollController,
      busy: widget.busy,
      downloadProgress: _downloadProgress,
      downloadToken: _downloadToken,
      statusListenable: _statusNotifier,
      loggedIn: widget.loggedIn,
      isParsing: _isParsing,
      onStartParse: _startParse,
      onCancelParse: _cancelParse,
      onCancelDownload: _cancelDownload,
      onPasteFromClipboard: _pasteFromClipboard,
      onRetry: _retryFailed,
      onTapAccount: widget.onTapAccount,
    );
  }
}
