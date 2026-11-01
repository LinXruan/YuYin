import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../services/douyin_sniffer.dart';
import '../services/video_downloader.dart';
import '../utils/log_controller.dart';
import '../utils/login_state_store.dart';
import '../utils/network_detector.dart';
import '../utils/url_parser.dart';
import '../widgets/image_preview_sheet.dart';
import '../widgets/video_quality_sheet.dart';

/// 解析页：粘贴链接 -> 嗅探 -> 选择画质/图片 -> 下载到相册
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
  });

  final DouyinSniffer sniffer;
  final VideoDownloader downloader;
  final LogController logs;
  final ValueNotifier<bool> busy;
  final ValueNotifier<bool> loggedIn;
  final VoidCallback onRequestParseTab;
  final VoidCallback? onTapAccount;

  @override
  State<ParsePage> createState() => _ParsePageState();
}

class _ParsePageState extends State<ParsePage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _inputScrollController = ScrollController();
  final ValueNotifier<double?> _downloadProgress = ValueNotifier(null);
  CancelToken? _downloadCancelToken;
  String _lastProgressKey = '';

  Timer? _hideScrollTimer;
  bool _showScrollIndicator = false;
  double _scrollProgress = 0.0;
  double _thumbHeight = 40.0;

  @override
  void dispose() {
    _hideScrollTimer?.cancel();
    _downloadCancelToken?.cancel('页面已销毁');
    _downloadCancelToken = null;
    _downloadProgress.dispose();
    _inputController.dispose();
    _inputScrollController.dispose();
    super.dispose();
  }

  /// 一键粘贴剪贴板内容
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      _inputController.text = data!.text!;
      if (_inputScrollController.hasClients) {
        _inputScrollController.jumpTo(0.0);
      }
    }
  }

  /// 监听输入框滚动：精确计算滑块尺寸与行程，防遮挡边框，停止后自动渐隐
  void _handleScrollNotification(ScrollNotification notification) {
    final metrics = notification.metrics;
    if (metrics.maxScrollExtent <= 0) {
      if (_showScrollIndicator) {
        setState(() => _showScrollIndicator = false);
      }
      return;
    }

    // 轨道有效高度：120dp 容器 - 顶部 8dp - 底部 8dp
    const double containerHeight = 120.0;
    const double topPadding = 8.0;
    const double bottomPadding = 8.0;
    const double trackHeight = containerHeight - topPadding - bottomPadding; // 104.0

    final double totalContentHeight =
        metrics.viewportDimension + metrics.maxScrollExtent;
    final double viewRatio = totalContentHeight > 0
        ? (metrics.viewportDimension / totalContentHeight).clamp(0.0, 1.0)
        : 1.0;
    // 文本量越大，viewRatio 越小，滑块越短；保底 20dp，上限 trackHeight - 12dp
    final double computedThumbHeight =
        (trackHeight * viewRatio).clamp(20.0, trackHeight - 12.0);

    final double progress =
        (metrics.pixels / metrics.maxScrollExtent).clamp(0.0, 1.0);

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

  /// 主流程：提取短链 -> 嗅探 -> 选择资源 -> 下载选中项
  Future<void> _startParse() async {
    if (widget.busy.value) return;
    FocusScope.of(context).unfocus();

    // 前置网络状态检测：离线时立即拦截并提示
    final hasNet = await NetworkDetector.hasInternetConnection();
    if (!mounted) return;
    if (!hasNet) {
      widget.logs.reset('网络未连接，无法解析');
      NetworkDetector.showOfflineSnackbar(context);
      return;
    }

    widget.logs.reset('正在提取短链...');
    _downloadProgress.value = null;
    _lastProgressKey = '';
    widget.busy.value = true;

    final url = UrlParser.extractDouyinUrl(_inputController.text);
    if (url == null) {
      widget.logs.add('未识别到有效的抖音链接，请检查粘贴内容');
      widget.busy.value = false;
      return;
    }

    try {
      widget.logs.add('正在解析作品...');
      final result = await widget.sniffer.sniffVideoUrl(url);
      if (!mounted) return;
      if (result.items.isEmpty) {
        widget.logs.add('未解析到可下载资源，请检查链接或稍后重试');
        return;
      }

      // 用户可能已切到其他 Tab，先切回解析页再弹选择面板
      widget.onRequestParseTab();
      final selected = await _chooseItems(result);
      if (!mounted) return;
      if (selected == null || selected.isEmpty) {
        // 取消后立即停止后台嗅探和网页加载，避免日志继续刷
        widget.sniffer.cancelActiveTask();
        widget.logs.add('已取消下载');
        return;
      }

      widget.logs.add('开始下载 ${selected.length} 个选中资源...');
      _downloadCancelToken = CancelToken();
      await widget.downloader.downloadItems(
        selected,
        cookie: result.cookie,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchProgress,
      );
      if (!mounted) return;
      widget.logs.add(
        selected.length == 1
            ? '已保存到相册！'
            : '全部 ${selected.length} 个资源已无水印保存至系统相册！',
      );
    } catch (error) {
      if (!mounted) return;
      widget.logs.add('操作失败：${_friendlyError(error)}');
    } finally {
      _downloadCancelToken = null;
      if (mounted) {
        widget.busy.value = false;
        _downloadProgress.value = null;
      }
    }
  }

  /// 根据作品类型弹出对应选择面板，返回用户选中的资源
  Future<List<MediaItem>?> _chooseItems(SniffResult result) async {
    if (result.isImagePost) {
      // 图文/实况图集：网格预览并勾选
      return ImagePreviewSheet.show(
        context,
        items: result.items,
        headers: const {
          'User-Agent': DouyinSniffer.desktopUserAgent,
          'Referer': 'https://www.douyin.com/',
        },
      );
    }

    // 普通视频：从全部清晰度档位中选择一个
    final picked = await VideoQualitySheet.show(context, result.items);
    if (picked == null) return null;
    final quality = picked.resolutionLabel.isNotEmpty
        ? picked.resolutionLabel
        : (picked.resolution ?? picked.gearName ?? '默认画质');
    widget.logs.add('已选择 $quality（${picked.formattedSize}）');
    return [picked];
  }

  /// 刷新批量下载进度（仅驱动局部进度条更新，避免触发整体界面重绘）
  void _updateBatchProgress(int current, int total, double itemProgress) {
    final percent = (itemProgress * 100).round();
    final key = '$current/$total/$percent';
    if (!mounted || key == _lastProgressKey) return;
    _lastProgressKey = key;

    // 总进度 = 已完成项 + 当前项进度
    final overall = total == 0 ? 0.0 : ((current - 1) + itemProgress) / total;
    widget.logs.upsertLast(
      '正在下载第',
      '正在下载第 $current/$total 个资源（$percent%）...',
    );
    _downloadProgress.value = overall.clamp(0.0, 1.0).toDouble();
  }

  /// 把异常转换成简短的中文提示
  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;
      return '嗅探超时，请检查链接是否有效后重试';
    }
    if (error is DioException && error.response?.statusCode == 403) {
      return '视频服务器拒绝了请求（403），请稍后重试';
    }
    return error.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
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
                                  color: theme.colorScheme.primary
                                      .withValues(alpha: 0.65),
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
                        onPressed: busy ? null : _pasteFromClipboard,
                        icon: const Icon(Icons.paste_rounded, size: 18),
                        label: const Text('粘贴'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  FilledButton.icon(
                    onPressed: busy ? null : _startParse,
                    icon: const Icon(Icons.download),
                    label: Text(busy ? '处理中...' : '解析作品'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
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
                  _StatusCard(logs: widget.logs),
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

/// 解析页底部的当前状态卡片：只显示最新一条日志
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.logs});

  final LogController logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<String>>(
      valueListenable: logs,
      builder: (context, value, _) {
        final status = value.isEmpty
            ? '就绪：粘贴抖音链接后点击“解析作品”'
            : value.last;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 未登录时展示的提示浮窗：跟随日志栏上下滚动，提示登录以获取更高画质
class _LoginPromptBanner extends StatefulWidget {
  const _LoginPromptBanner({
    required this.loggedIn,
    this.onTapLogin,
  });

  final ValueNotifier<bool> loggedIn;
  final VoidCallback? onTapLogin;

  @override
  State<_LoginPromptBanner> createState() => _LoginPromptBannerState();
}

class _LoginPromptBannerState extends State<_LoginPromptBanner> {
  bool _sessionDismissed = false;
  bool _permanentlyDismissed = false;

  @override
  void initState() {
    super.initState();
    LoginStateStore.isLoginPromptDismissed().then((dismissed) {
      if (mounted && dismissed) {
        setState(() => _permanentlyDismissed = true);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.loggedIn,
      builder: (context, loggedIn, _) {
        if (loggedIn || _sessionDismissed || _permanentlyDismissed) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;

        // 亮/暗双模式精细化卡片配色
        final backgroundColor = isDark
            ? const Color(0xFF261F22)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.28);
        final borderColor = isDark
            ? const Color(0xFF7B2949).withValues(alpha: 0.6)
            : theme.colorScheme.primary.withValues(alpha: 0.25);
        final iconColor =
            isDark ? const Color(0xFFFFB0C8) : theme.colorScheme.primary;
        final textColor =
            isDark ? const Color(0xFFECE0E2) : theme.colorScheme.onSurface;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: 1.0),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              InkWell(
                onTap: widget.onTapLogin,
                borderRadius: BorderRadius.circular(8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        Icons.tips_and_updates_outlined,
                        size: 20,
                        color: iconColor,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '建议登录抖音，可以解析到更高画质',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: textColor,
                          fontWeight: FontWeight.w500,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () {
                      setState(() => _sessionDismissed = true);
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isDark
                          ? const Color(0xFFD4C2C6)
                          : theme.colorScheme.onSurfaceVariant,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    child: const Text('关闭'),
                  ),
                  const SizedBox(width: 4),
                  TextButton(
                    onPressed: () async {
                      setState(() => _permanentlyDismissed = true);
                      await LoginStateStore.setLoginPromptDismissed(true);
                    },
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      foregroundColor: isDark
                          ? const Color(0xFFFFB0C8)
                          : theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                    ),
                    child: const Text('不再显示'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}
