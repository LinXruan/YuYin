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
import '../utils/save_location_store.dart';
import '../utils/url_parser.dart';
import '../widgets/image_preview_sheet.dart';
import '../widgets/multi_home_preview_sheet.dart';
import '../models/history_item.dart';
import '../utils/history_store.dart';
import '../widgets/video_quality_sheet.dart';

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

  /// 用户主动终止当前解析流程
  void _cancelParse() {
    if (!_isParsing) return;
    _isParsing = false;
    if (mounted) setState(() {});
    widget.sniffer.cancelActiveTask();
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

  /// 主流程：提取短链 -> 捕获 -> 选择资源 -> 下载选中项
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
    _isParsing = true;
    _cancelLogged = false;
    if (mounted) setState(() {});

    final batch = UrlParser.parseBatchInput(_inputController.text);
    if (batch.kind == ParsedBatchKind.empty) {
      widget.logs.add('未识别到有效的抖音链接，请检查粘贴内容');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) setState(() {});
      return;
    }

    if (batch.kind == ParsedBatchKind.mixed) {
      widget.logs.add('检测到同时包含主页链接和作品链接，请分开粘贴解析');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) setState(() {});
      return;
    }

    if (batch.kind == ParsedBatchKind.multiWork) {
      // 多作品链接：预留跳转至中层保存页（待后续 PLAN 实现）
      widget.logs.add('已识别 ${batch.workUrls.length} 个作品链接，多作品中层保存页待后续开发');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) setState(() {});
      return;
    }

    if (batch.kind == ParsedBatchKind.userHomes) {
      await _parseUserHomes(batch.homeUrls);
      return;
    }

    final url = batch.workUrls.first;

    try {
      widget.logs.add('正在解析作品...');
      final result = await widget.sniffer.sniffVideoUrl(url);
      if (!mounted || !_isParsing) return;
      _isParsing = false;
      if (mounted) setState(() {});

      if (result.items.isEmpty) {
        widget.logs.add('未解析到可下载资源，请检查链接或稍后重试');
        return;
      }

      // 记录成功解析作品到历史记录中
      final historyDesc = (result.desc?.trim().isNotEmpty ?? false)
          ? result.desc!.trim()
          : (result.title?.trim().isNotEmpty ?? false
              ? result.title!.trim()
              : (UrlParser.extractShareText(_inputController.text) ?? _inputController.text));

      String? historyCover = (result.coverUrl?.trim().isNotEmpty ?? false)
          ? result.coverUrl!.trim()
          : null;
      if (historyCover == null) {
      for (final it in result.items) {
        if (it.type == MediaType.image && it.url.isNotEmpty) {
          historyCover = it.url;
          break;
        }
      }
      }
      // 严格禁止将视频文件直链作为封面兜底，保持纯正图片直链或 null

      final summaryTags = <String>[];
      if (result.videoCount > 0) summaryTags.add(result.isImagePost ? '实况' : '视频');
      if (result.imageCount > 0) summaryTags.add('图集');
      if (result.audioCount > 0) summaryTags.add('音频');
      summaryTags.add('文案');

      HistoryStore.addRecord(
        HistoryItem(
          id: url,
          url: url,
          rawInput: _inputController.text,
          fullDesc: historyDesc,
          title: result.title,
          coverUrl: historyCover,
          isImagePost: result.isImagePost,
          mediaSummary: summaryTags.join('/'),
          itemCount: result.items.length,
          createdAt: DateTime.now(),
        ),
      );

      // 用户可能已切到其他 Tab，先切回解析页再弹选择面板
      widget.onRequestParseTab();
      final selected = await _chooseItems(result);
      if (!mounted) return;
      if (selected == null || selected.isEmpty) {
        // 取消后立即停止后台捕获和网页加载，避免日志继续刷
        widget.sniffer.cancelActiveTask();
        widget.logs.add('已取消下载');
        return;
      }

      // 命名基准：专攻作品文案（desc），若未捕获则从用户粘贴文本/口令中提取纯文案兜底
      final candidateDesc = (result.desc?.trim().isNotEmpty ?? false)
          ? result.desc!.trim()
          : UrlParser.extractShareText(_inputController.text);

      widget.logs.add('开始下载 ${selected.length} 个选中资源...');
      _downloadCancelToken = CancelToken();
      final savedTypes = await widget.downloader.downloadItems(
        selected,
        cookie: result.cookie,
        baseTitle: candidateDesc,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchProgress,
      );
      if (!mounted) return;
      if (savedTypes.isNotEmpty) {
        HistoryStore.markSaved(url, true);
      }
      if (savedTypes.contains(MediaType.image)) {
        widget.logs.add('图片已保存到${SaveLocationStore.getDisplayPath(MediaType.image)}');
      }
      if (savedTypes.contains(MediaType.video)) {
        widget.logs.add('视频已保存到${SaveLocationStore.getDisplayPath(MediaType.video)}');
      }
      if (savedTypes.contains(MediaType.audio)) {
        widget.logs.add('音频已保存到${SaveLocationStore.getDisplayPath(MediaType.audio)}');
      }
    } catch (error) {
      if (!mounted) return;
      final errorText = error.toString();
      if (errorText.contains('用户已取消解析')) {
        if (!_cancelLogged) {
          _cancelLogged = true;
          widget.logs.add('已取消解析');
        }
      } else {
        widget.logs.add('操作失败：${_friendlyError(error)}');
      }
    } finally {
      _downloadCancelToken = null;
      if (mounted) {
        _isParsing = false;
        widget.busy.value = false;
        _downloadProgress.value = null;
        setState(() {});
      }
    }
  }

  /// 批量捕获多主页作者头像与昵称，成功后弹出顶层保存页
  Future<void> _parseUserHomes(List<String> homeUrls) async {
    bool isLogged = widget.loggedIn.value;
    if (!isLogged) {
      try {
        isLogged = await LoginStateStore.isLoggedIn() &&
            await LoginStateStore.checkWebViewCookieSession();
        if (isLogged) widget.loggedIn.value = true;
      } catch (_) {}
    }

    if (!isLogged) {
      widget.logs.add('请登录再进行主页链接解析');
      widget.busy.value = false;
      _isParsing = false;
      if (mounted) setState(() {});
      return;
    }

    final authors = <MultiHomeAuthorItem>[];
    try {
      for (var i = 0; i < homeUrls.length; i++) {
        if (!mounted || !_isParsing) return;
        widget.logs.add('正在捕获作者信息 (${i + 1}/${homeUrls.length})...');
        try {
          final profile =
              await widget.sniffer.userHome.extractProfile(homeUrls[i]);
          if (!mounted || !_isParsing) return;
          authors.add(MultiHomeAuthorItem(profile: profile));
        } catch (e) {
          if (!mounted || !_isParsing) return;
          widget.logs.add('第 ${i + 1} 个主页捕获失败：${_friendlyError(e)}');
        }
      }

      _isParsing = false;
      if (mounted) setState(() {});

      if (authors.isEmpty) {
        widget.logs.add('未捕获到有效作者信息，请检查主页链接或登录状态');
        return;
      }

      if (!mounted) return;
      widget.logs.add('[主页] 成功捕获 ${authors.length} 位作者信息，正在打开顶层保存页');
      widget.onRequestParseTab();
      final selection = await MultiHomePreviewSheet.show(
        context,
        authors: authors,
        headers: const {
          'User-Agent': DouyinSniffer.desktopUserAgent,
          'Referer': 'https://www.douyin.com/',
        },
      );
      if (!mounted) return;
      if (selection == null) {
        widget.logs.add('已取消多主页保存');
        return;
      }

      final qualityLabel = switch (selection.qualityMode) {
        BatchVideoQualityMode.highest => '最高画质',
        BatchVideoQualityMode.lowest => '最低画质',
        BatchVideoQualityMode.mixed => '混合画质',
      };
      widget.logs.add(
        '已选择 ${selection.selectedAuthors.length} 位作者（画质：$qualityLabel），批量下载逻辑待后续接入',
      );
    } finally {
      if (mounted) {
        widget.busy.value = false;
        _isParsing = false;
        setState(() {});
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
      return '捕获超时，请检查链接是否有效后重试';
    }
    if (error is DioException && error.response?.statusCode == 403) {
      return '视频服务器拒绝了请求（403），请稍后重试';
    }
    return error
        .toString()
        .replaceFirst(RegExp(r'^(Exception|Bad state|FormatException): '), '');
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
/// 过程态保持单行极简显示，完成态（下载落盘）智能聚合多分类保存路径全量展示
class StatusCard extends StatelessWidget {
  const StatusCard({super.key, required this.logs});

  final LogController logs;

  /// 智能状态文本解析器：
  /// - 尾部包含“已保存到”时，向前聚拢本次任务全部连续的保存路径提示；
  /// - 其余过程态（提取短链、网页捕获、下载进度等）严格单行返回最新一条状态。
  static String resolveStatusText(List<String> logs) {
    if (logs.isEmpty) {
      return '就绪：粘贴抖音链接后点击“解析作品”';
    }
    final last = logs.last;
    if (last.contains('已保存到')) {
      final savePrompts = <String>[];
      for (var i = logs.length - 1; i >= 0; i--) {
        final line = logs[i];
        if (line.contains('已保存到')) {
          savePrompts.insert(0, line);
        } else {
          break;
        }
      }
      return savePrompts.join('\n');
    }
    return last;
  }

  /// 当前是否处于下载完成落盘状态
  static bool isCompletionStatus(List<String> logs) {
    return logs.isNotEmpty && logs.last.contains('已保存到');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = theme.brightness == Brightness.dark;

    return ValueListenableBuilder<List<String>>(
      valueListenable: logs,
      builder: (context, value, _) {
        final status = resolveStatusText(value);
        final isSuccess = isCompletionStatus(value);

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: isSuccess
                ? colorScheme.primary.withValues(alpha: isDark ? 0.16 : 0.08)
                : colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: isSuccess
                ? Border.all(
                    color: colorScheme.primary.withValues(alpha: isDark ? 0.35 : 0.25),
                  )
                : null,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isSuccess ? Icons.check_circle_outline : Icons.info_outline,
                size: 18,
                color: isSuccess
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    height: 1.5,
                    color: isSuccess
                        ? colorScheme.onSurface
                        : colorScheme.onSurfaceVariant,
                    fontWeight: isSuccess ? FontWeight.w500 : FontWeight.normal,
                  ),
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
