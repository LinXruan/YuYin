import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../../../models/parse/parse_status.dart';
import '../../../../utils/login_state_store.dart';
import '../../../../utils/settings/parse_hint_store.dart';
import '../banner/batch_support_banner.dart';
import '../banner/login_prompt_banner.dart';
import '../status/status_card.dart';
import 'parse_action_button.dart';

/// 解析页纯 UI 骨架：输入框、定制滑动指示器、操作按钮、进度条与提示横幅
class ParseFrame extends StatefulWidget {
  const ParseFrame({
    super.key,
    required this.inputController,
    required this.inputScrollController,
    required this.busy,
    required this.downloadProgress,
    required this.downloadToken,
    required this.statusListenable,
    required this.loggedIn,
    required this.isParsing,
    required this.onStartParse,
    required this.onCancelParse,
    required this.onCancelDownload,
    required this.onPasteFromClipboard,
    this.loginStateStore,
    this.parseHintStore,
    this.onRetry,
    this.onTapAccount,
  });

  final TextEditingController inputController;
  final ScrollController inputScrollController;
  final ValueNotifier<bool> busy;
  final ValueNotifier<double?> downloadProgress;
  final ValueNotifier<CancelToken?> downloadToken;
  final ValueListenable<ParseStatus> statusListenable;
  final ValueNotifier<bool> loggedIn;
  final bool isParsing;
  final VoidCallback onStartParse;
  final VoidCallback onCancelParse;
  final VoidCallback onCancelDownload;
  final VoidCallback onPasteFromClipboard;
  final LoginStateStore? loginStateStore;
  final ParseHintStore? parseHintStore;
  final ValueChanged<List<String>>? onRetry;
  final VoidCallback? onTapAccount;

  @override
  State<ParseFrame> createState() => _ParseFrameState();
}

class _ParseFrameState extends State<ParseFrame> {
  Timer? _hideScrollTimer;
  bool _showScrollIndicator = false;
  double _scrollProgress = 0.0;
  double _thumbHeight = 40.0;

  @override
  void dispose() {
    _hideScrollTimer?.cancel();
    super.dispose();
  }

  void _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) {
      if (_showScrollIndicator) {
        setState(() => _showScrollIndicator = false);
      }
      return;
    }

    const double containerHeight = 120.0;
    const double topPadding = 8.0;
    const double bottomPadding = 8.0;
    const double trackHeight = containerHeight - topPadding - bottomPadding;

    final double totalContentHeight =
        metrics.viewportDimension + metrics.maxScrollExtent;
    final double viewRatio = totalContentHeight > 0
        ? (metrics.viewportDimension / totalContentHeight).clamp(0.0, 1.0)
        : 1.0;
    final double computedThumbHeight = (trackHeight * viewRatio).clamp(
      20.0,
      trackHeight - 12.0,
    );

    final double progress = (metrics.pixels / metrics.maxScrollExtent).clamp(
      0.0,
      1.0,
    );

    setState(() {
      _scrollProgress = progress;
      _thumbHeight = computedThumbHeight;
      _showScrollIndicator = true;
    });

    _hideScrollTimer?.cancel();
    _hideScrollTimer = Timer(const Duration(milliseconds: 1200), () {
      if (mounted) {
        setState(() => _showScrollIndicator = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
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
                            controller: widget.inputController,
                            scrollController: widget.inputScrollController,
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
                        onPressed: widget.onPasteFromClipboard,
                        icon: const Icon(Icons.paste_rounded, size: 18),
                        label: const Text('清除并粘贴'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : widget.onStartParse,
                          icon: const Icon(Icons.download),
                          label: Text(busy ? '处理中...' : '解析作品'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      ParseActionButton(
                        token: widget.downloadToken,
                        isParsing: widget.isParsing,
                        onCancelParse: widget.onCancelParse,
                        onCancelDownload: widget.onCancelDownload,
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<double?>(
                    valueListenable: widget.downloadProgress,
                    builder: (context, progress, _) {
                      return LinearProgressIndicator(
                        value: busy ? progress : 0,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  StatusCard(
                    statusListenable: widget.statusListenable,
                    onRetry: widget.onRetry,
                  ),
                  const SizedBox(height: 12),
                  LoginPromptBanner(
                    loggedIn: widget.loggedIn,
                    loginStateStore: widget.loginStateStore,
                    onTapLogin: widget.onTapAccount,
                  ),
                  const SizedBox(height: 8),
                  BatchSupportBanner(parseHintStore: widget.parseHintStore),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
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
