import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/common/save_memory_scope.dart';
import '../models/media_item.dart';
import '../models/save_page/author_works_selection.dart';
import '../services/batch_work/work_batch_saver.dart';
import '../services/douyin_sniffer.dart';
import '../services/multi_work/article_work_exception.dart';
import '../services/user_home/user_home_batch_saver.dart';
import '../services/video_downloader.dart';
import '../utils/download_settings_store.dart';
import '../utils/file_name_formatter.dart';
import '../utils/log_controller.dart';
import '../utils/login_state_store.dart';
import '../utils/network_detector.dart';
import '../utils/save_location_store.dart';
import '../utils/url_parser.dart';
import '../utils/video_quality_utils.dart';
import '../widgets/image_preview_sheet.dart';
import '../widgets/multi_home_preview_sheet.dart';
import '../models/history_item.dart';
import '../utils/history_store.dart';
import '../widgets/save_page/middle_multi_work_sheet.dart';
import '../widgets/video_quality_sheet.dart';

part 'parse/flow/common/parse_input_flow.dart';

part 'parse/flow/single/single_parse_flow.dart';

part 'parse/flow/home/home_parse_flow.dart';

part 'parse/flow/multi/multi_parse_flow.dart';

part 'parse/flow/common/parse_progress_flow.dart';
part 'parse/widget/status/status_card.dart';
part 'parse/widget/banner/login_prompt_banner.dart';
part 'parse/support/home_works_delegate.dart';

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

  /// 作者主页作品列表缓存（key: secUid），用于重复进入中层时恢复选择
  final Map<String, List<SaveWorkItem>> _authorWorksCache = {};

  /// 加载封面/头像所需的统一请求头
  static const Map<String, String> _mediaHeaders = {
    'User-Agent': DouyinSniffer.desktopUserAgent,
    'Referer': 'https://www.douyin.com/',
  };

  /// 批量作品保存器（下载器与嗅探器均实现对应代理）
  WorkBatchSaver get _workBatchSaver => WorkBatchSaver(
        downloader: widget.downloader,
        sniffer: widget.sniffer,
      );

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
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.busy,
            builder: (context, busy, _) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(
                    height: 120,
                    child: Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.depth == 0) {
                              _handleScrollNotification(notification);
                            }
                            return false;
                          },
                          child: TextField(
                            controller: _inputController,
                            scrollController: _inputScrollController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              labelText: '抖音分享口令 / 链接',
                              hintText:
                                  '粘贴分享口令或链接，例如 https://v.douyin.com/xxxx/',
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                          ),
                        ),
                        // 悬浮定制滑动指示器：无手势劫持、向左微调防遮挡边框、不滑动渐隐
                        Positioned(
                          top: 8.0 + (_scrollProgress * (104.0 - _thumbHeight)),
                          right: 7.0,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _showScrollIndicator ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 250),
                              child: Container(
                                width: 3.0,
                                height: _thumbHeight,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.65,
                                  ),
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.paste_rounded, size: 18),
                        label: const Text('粘贴'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : _startParse,
                          icon: const Icon(Icons.download),
                          label: Text(busy ? '处理中...' : '解析作品'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      if (_isParsing) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: _cancelParse,
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: '终止解析',
                          style: IconButton.styleFrom(
                            shape: const CircleBorder(),
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<double?>(
                    valueListenable: _downloadProgress,
                    builder: (context, progress, _) {
                      return LinearProgressIndicator(
                        value: busy ? progress : 0,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  StatusCard(logs: widget.logs),
                  const SizedBox(height: 12),
                  _LoginPromptBanner(
                    loggedIn: widget.loggedIn,
                    onTapLogin: widget.onTapAccount,
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
        // 页面底部标识文字（仅展示，不可点击）
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            '本地、解析、隐私',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }
}

/// 解析页底部的当前状态卡片：
