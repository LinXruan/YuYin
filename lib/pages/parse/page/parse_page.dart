import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/media_item.dart';
import '../../../services/batch_work/work_batch_saver.dart';
import '../../../services/sniffer/facade/douyin_sniffer.dart';
import '../../../services/multi_work/article_work_exception.dart';
import '../../../services/user_home/user_home_batch_saver.dart';
import '../../../services/media/video_downloader.dart';
import '../../../utils/save/file_name_formatter.dart';
import '../../../utils/debug/log_controller.dart';
import '../../../utils/login_state_store.dart';
import '../../../utils/network_detector.dart';
import '../../../utils/savelocation/save_location_store.dart';
import '../../../utils/memory/terminal_memory_store.dart';
import '../../../utils/url_parser.dart';
import '../../../utils/settings/video_quality_utils.dart';
import '../../../models/history_item.dart';
import '../../../utils/history/history_store.dart';
import '../../../services/selection/debug/selection_debug_bridge.dart';
import '../../../services/selection/save_selection_session.dart';
import '../../../services/selection/session_work_preparer.dart';
import '../../../widgets/save_page/bottom_media_sheet.dart';
import '../../../widgets/save_page/middle_multi_work_sheet.dart';
import '../../../widgets/save_page/top_multi_home_sheet.dart';
import '../../../widgets/save_page/bottom/widget/video_tier_picker_sheet.dart';

part '../flow/common/parse_input_flow.dart';

part '../flow/single/single_parse_flow.dart';

part '../flow/home/home_parse_flow.dart';

part '../flow/multi/multi_parse_flow.dart';

part '../flow/common/parse_progress_flow.dart';
part '../widget/status/status_card.dart';
part '../widget/banner/login_prompt_banner.dart';
part '../flow/common/save_page_flow.dart';

part '../widget/frame/parse_frame.dart';

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
  final ValueNotifier<double?> _downloadProgress = ValueNotifier(null);
  CancelToken? _downloadCancelToken;
  String _lastProgressKey = '';

  Timer? _hideScrollTimer;
  bool _showScrollIndicator = false;
  double _scrollProgress = 0.0;
  double _thumbHeight = 40.0;
  bool _isParsing = false;
  bool _cancelLogged = false;

  /// 加载封面/头像所需的统一请求头
  static const Map<String, String> _mediaHeaders = {
    'User-Agent': DouyinSniffer.desktopUserAgent,
    'Referer': 'https://www.douyin.com/',
  };

  /// 批量作品保存器（下载器与嗅探器均实现对应代理）
  WorkBatchSaver get _workBatchSaver =>
      WorkBatchSaver(downloader: widget.downloader);

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
  }

  /// 供流程分片调用的状态刷新入口（setState 受保护，扩展无法直接调用）
  void _refresh(VoidCallback fn) => setState(fn);

  @override
  void dispose() {
    widget.externalUrlNotifier?.removeListener(_onExternalUrlChanged);
    _hideScrollTimer?.cancel();
    if (_isParsing) {
      widget.sniffer.cancelActiveTask();
    }
    _downloadCancelToken?.cancel('页面已销毁');
    _downloadCancelToken = null;
    _downloadProgress.dispose();
    _inputController.dispose();
    _inputScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return _buildParsePage(context);
  }
}

/// 解析页底部的当前状态卡片：