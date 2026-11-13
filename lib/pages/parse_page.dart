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
    const double trackHeight =
        containerHeight - topPadding - bottomPadding; // 104.0

    final double totalContentHeight =
        metrics.viewportDimension + metrics.maxScrollExtent;
    final double viewRatio = totalContentHeight > 0
        ? (metrics.viewportDimension / totalContentHeight).clamp(0.0, 1.0)
        : 1.0;
    // 文本量越大，viewRatio 越小，滑块越短；保底 20dp，上限 trackHeight - 12dp
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

    if (batch.filteredArticleCount > 0) {
      widget.logs.add('已自动过滤 ${batch.filteredArticleCount} 条文章作品链接');
    }

    if (batch.kind == ParsedBatchKind.articlesOnly) {
      widget.logs.add('未识别到可下载的视频/图文作品（文章作品暂不支持）');
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
      await _parseMultiWorks(batch.workUrls);
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
                : (UrlParser.extractShareText(_inputController.text) ??
                      _inputController.text));

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
      if (result.videoCount > 0) {
        summaryTags.add(result.isImagePost ? '实况' : '视频');
      }
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
      final baseName = FileNameFormatter.sanitize(
        FileNameFormatter.buildBaseName(candidateDesc),
      );
      _downloadCancelToken = CancelToken();
      final savedTypes = await widget.downloader.downloadItems(
        selected,
        cookie: result.cookie,
        baseTitle: baseName,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchProgress,
      );
      if (!mounted) return;
      if (savedTypes.isNotEmpty) {
        HistoryStore.markSavedWithMeta(url, savedBaseName: baseName);
      }
      if (savedTypes.contains(MediaType.image)) {
        widget.logs.add(
          '图片已保存到${SaveLocationStore.getDisplayPath(MediaType.image)}',
        );
      }
      if (savedTypes.contains(MediaType.video)) {
        widget.logs.add(
          '视频已保存到${SaveLocationStore.getDisplayPath(MediaType.video)}',
        );
      }
      if (savedTypes.contains(MediaType.audio)) {
        widget.logs.add(
          '音频已保存到${SaveLocationStore.getDisplayPath(MediaType.audio)}',
        );
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
        isLogged =
            await LoginStateStore.isLoggedIn() &&
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
    final seenHomeKeys = <String>{};
    // 明确 /user/ 网址优先于口令短链，避免同一主页重复抓取
    final orderedHomeUrls = <String>[
      ...homeUrls.where(UrlParser.isUserHomeUrl),
      ...homeUrls.where((url) => !UrlParser.isUserHomeUrl(url)),
    ];
    try {
      for (var i = 0; i < orderedHomeUrls.length; i++) {
        if (!mounted || !_isParsing) return;
        final homeUrl = orderedHomeUrls[i];
        widget.logs.add(
          '正在捕获主页作品 (${i + 1}/${orderedHomeUrls.length})...',
        );
        try {
          // 一次性抓取作者资料 + 全部作品链接/封面，顶层页打开后进入中层无需再等待
          final homeResult = await widget.sniffer.userHome.extractAllWorks(
            homeUrl,
          );
          if (!mounted || !_isParsing) return;

          final secUid = homeResult.secUid.trim();
          if (secUid.isEmpty) {
            widget.logs.add('第 ${i + 1} 个主页未识别到 secUid，已跳过');
            continue;
          }
          if (!seenHomeKeys.add(secUid)) {
            widget.logs.add(
              '重复主页已去重（同一作者的口令与网址）: ${homeResult.nickname}',
            );
            continue;
          }

          final works = _buildHomeWorks(homeResult);
          if (works.isEmpty) {
            widget.logs.add(
              '作者【${homeResult.nickname.isNotEmpty ? homeResult.nickname : "未知作者"}】暂无可保存作品，已跳过',
            );
            continue;
          }
          _authorWorksCache[secUid] = works;
          HistoryStore.addRecord(
            HistoryItem(
              id: 'home:$secUid',
              url: 'https://www.douyin.com/user/$secUid',
              rawInput: homeUrl,
              fullDesc: homeResult.nickname,
              title: homeResult.nickname,
              coverUrl: homeResult.avatarUrl,
              mediaSummary: '作者主页',
              itemCount: works.length,
              recordType: HistoryRecordType.userHome,
              authorSecUid: secUid,
            ),
          );
          authors.add(
            MultiHomeAuthorItem(
              profile: homeResult.profile,
              worksTotalTag: homeResult.worksTotalTag,
            ),
          );
          final articleText = homeResult.filteredArticleCount > 0
              ? '，已过滤 ${homeResult.filteredArticleCount} 条文章'
              : '';
          widget.logs.add(
            '作者【${homeResult.nickname.isNotEmpty ? homeResult.nickname : "未知作者"}】'
            '作品捕获完成：${works.length} 条可保存，'
            '已关联封面 ${homeResult.coversCount} 条$articleText',
          );
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
        headers: _mediaHeaders,
        initialWorksBySecUid: _authorWorksCache,
        memoryScope: SaveMemoryScope.homeTop,
        onOpenAuthor: _openAuthorWorks,
      );
      if (!mounted) return;
      if (selection == null) {
        widget.logs.add('已取消多主页保存');
        return;
      }

      final selectedAuthors = selection.selectedAuthors;
      if (selectedAuthors.isEmpty) {
        widget.logs.add('未选择任何作者');
        return;
      }

      final homeSaver = UserHomeBatchSaver(
        workSaver: _workBatchSaver,
        delegate: _HomeWorksDelegate(_extractWorksForBatch),
      );
      widget.busy.value = true;
      _downloadCancelToken = CancelToken();
      widget.logs.add(
        '开始保存 ${selectedAuthors.length} 位作者（${_qualityLabel(selection.qualityMode)}）...',
      );

      final result = await homeSaver.saveAuthors(
        authors: selectedAuthors,
        worksBySecUid: selection.worksBySecUid,
        qualityMode: selection.qualityMode,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchSaveProgress,
        onLog: (message) {
          if (mounted) widget.logs.add(message);
        },
      );
      if (!mounted) return;

      for (final author in result.authors) {
        if (author.success) {
          HistoryStore.markSaved('home:${author.secUid}', true);
        }
      }

      final successCount = result.authors.where((a) => a.success).length;
      widget.logs.add(
        '主页批量保存完成：成功 $successCount/${result.authors.length} 位作者，共 ${result.totalSaved} 项资源',
      );
    } on DouyinDownloadCancelledException {
      if (mounted) widget.logs.add('已取消主页批量保存');
    } finally {
      if (mounted) {
        widget.busy.value = false;
        _isParsing = false;
        _downloadProgress.value = null;
        setState(() {});
      }
    }
  }

  /// 粘贴多个作品链接：逐条捕获封面后打开中层保存页
  Future<void> _parseMultiWorks(List<String> workUrls) async {
    try {
      widget.logs.add('已识别 ${workUrls.length} 个作品链接，开始逐条捕获封面...');
      final extractResult = await widget.sniffer.multiWork.extractWorks(
        workUrls,
        onProgress: (current, total, message) {
          if (!mounted) return;
          widget.logs.upsertLast('正在捕获作品封面', message);
        },
        onLog: (message) {
          if (mounted) widget.logs.add(message);
        },
      );
      if (!mounted || !_isParsing) return;

      widget.logs.add(
        '作品封面捕获完成：${extractResult.works.length} 条可保存，'
        '${extractResult.filteredArticleCount} 条文章已过滤，'
        '${extractResult.failedCount} 条失败',
      );

      if (extractResult.works.isEmpty) {
        widget.logs.add('未捕获到可保存的作品');
        return;
      }

      // 多作品链接解析：每个作品写入一条独立历史记录
      for (final work in extractResult.works) {
        final parsed = work.parsedResult;
        final desc = (parsed?.desc?.trim().isNotEmpty ?? false)
            ? parsed!.desc!.trim()
            : (work.title.trim().isNotEmpty ? work.title.trim() : work.url);
        HistoryStore.addRecord(
          HistoryItem(
            id: work.url,
            url: work.url,
            rawInput: _inputController.text,
            fullDesc: desc,
            title: work.title,
            coverUrl: work.coverUrl,
            isImagePost: work.kind == WorkMediaKind.image,
            mediaSummary: _mediaSummaryFor(parsed, work.kind),
            itemCount: parsed?.items.length ?? 1,
          ),
        );
      }

      _isParsing = false;
      if (mounted) setState(() {});
      widget.onRequestParseTab();
      final selection = await MiddleMultiWorkSheet.show(
        context,
        works: extractResult.works,
        headers: _mediaHeaders,
        nested: false,
        initialQualityMode: DownloadSettingsStore.getBatchQuality(
          SaveMemoryScope.multiMiddle,
        ),
        memoryScope: SaveMemoryScope.multiMiddle,
        onOpenWork: (work, index) =>
            _openWorkDetail(work, index, SaveMemoryScope.multiBottom),
      );
      if (!mounted) return;
      if (selection == null) {
        widget.logs.add('已取消多作品保存');
        return;
      }

      final selectedWorks = selection.selectedWorks;
      if (selectedWorks.isEmpty) {
        widget.logs.add('未选择任何作品');
        return;
      }

      widget.busy.value = true;
      _downloadCancelToken = CancelToken();
      widget.logs.add(
        '开始保存 ${selectedWorks.length} 个作品（${_qualityLabel(selection.qualityMode)}）...',
      );

      final results = await _workBatchSaver.saveWorks(
        selectedWorks,
        qualityMode: selection.qualityMode,
        cancelToken: _downloadCancelToken,
        onProgress: _updateBatchSaveProgress,
        onLog: (message) {
          if (mounted) widget.logs.add(message);
        },
      );
      if (!mounted) return;

      for (final item in results) {
        if (item.success) {
          HistoryStore.markSavedWithMeta(
            item.url,
            savedBaseName: item.savedBaseName,
          );
        }
      }

      final successCount = results.where((item) => item.success).length;
      widget.logs.add('多作品保存完成：成功 $successCount/${results.length}');
    } on DouyinDownloadCancelledException {
      if (mounted) widget.logs.add('已取消多作品保存');
    } catch (e) {
      if (mounted) {
        widget.logs.add('多作品捕获失败：${_friendlyError(e)}');
      }
    } finally {
      if (mounted) {
        widget.busy.value = false;
        _isParsing = false;
        _downloadProgress.value = null;
        setState(() {});
      }
    }
  }

  /// 顶层点击作者“打开”：使用顶层当前作品树与画质进入中层
  Future<AuthorWorksSelection?> _openAuthorWorks(
    MultiHomeAuthorItem author,
    int index,
    List<SaveWorkItem> topWorks,
    BatchVideoQualityMode topQuality,
  ) async {
    final secUid = author.profile.secUid.trim();
    if (secUid.isEmpty) {
      widget.logs.add('作者 secUid 缺失，无法捕获作品列表');
      return null;
    }

    var works = topWorks;
    if (works.isEmpty) {
      works = _authorWorksCache[secUid] ?? const [];
    }
    if (works.isEmpty) {
      final nickname = author.profile.nickname.isNotEmpty
          ? author.profile.nickname
          : '未知作者';
      widget.logs.add('正在捕获作者【$nickname】的作品列表...');
      try {
        final homeResult = await widget.sniffer.userHome.extractAllWorks(
          'https://www.douyin.com/user/$secUid',
        );
        if (!mounted) return null;
        works = _buildHomeWorks(homeResult);
        _authorWorksCache[secUid] = works;
        final articleText = homeResult.filteredArticleCount > 0
            ? '（已过滤 ${homeResult.filteredArticleCount} 条文章）'
            : '';
        widget.logs.add(
          '作者【$nickname】作品列表捕获完成：${works.length} 条可保存作品$articleText',
        );
      } catch (e) {
        if (mounted) {
          widget.logs.add('捕获作者作品列表失败：${_friendlyError(e)}');
        }
        return null;
      }
    }

    if (works.isEmpty) {
      widget.logs.add('该作者暂无可保存的视频/图文作品');
      return null;
    }

    if (!mounted) return null;
    final selection = await MiddleMultiWorkSheet.show(
      context,
      works: works,
      headers: _mediaHeaders,
      nested: true,
      // 顶层已经应用过记忆与用户操作，禁止中层再用记忆覆盖
      useMemoryDefault: false,
      initialQualityMode: topQuality,
      memoryScope: SaveMemoryScope.homeMiddle,
      onOpenWork: (work, index) =>
          _openWorkDetail(work, index, SaveMemoryScope.homeBottom),
    );
    if (!mounted || selection == null) return null;

    _authorWorksCache[secUid] = selection.allWorks;
    return AuthorWorksSelection(
      works: selection.allWorks,
      qualityMode: selection.qualityMode,
    );
  }

  /// 将主页捕获结果转换为中层作品条目（过滤文章并区分视频/图文）
  List<SaveWorkItem> _buildHomeWorks(UserHomeResult result) {
    final works = <SaveWorkItem>[];
    for (final url in result.workUrls) {
      if (UrlParser.isArticleUrl(url)) continue;
      final kind = UrlParser.classifyWorkPage(url) == DouyinWorkPage.note
          ? WorkMediaKind.image
          : WorkMediaKind.video;
      works.add(
        SaveWorkItem(
          url: url,
          kind: kind,
          title: result.getTitle(url) ?? '',
          coverUrl: result.getCover(url) ?? '',
        ),
      );
    }
    return works;
  }

  /// 顶层保存时补抓某个作者的作品列表
  Future<List<SaveWorkItem>> _extractWorksForBatch(String secUid) async {
    final homeResult = await widget.sniffer.userHome.extractAllWorks(
      'https://www.douyin.com/user/$secUid',
    );
    return _buildHomeWorks(homeResult);
  }

  /// 中层点击作品“打开”：按需解析作品并进入底层资源/画质选择
  Future<WorkDetailSelection?> _openWorkDetail(
    SaveWorkItem work,
    int index,
    SaveMemoryScope bottomScope,
  ) async {
    var result = work.parsedResult;
    if (result == null) {
      final title = work.title.trim().isNotEmpty ? work.title.trim() : work.url;
      widget.logs.add('正在解析作品：$title');
      try {
        result = await widget.sniffer.sniffVideoUrl(work.url);
      } on ArticleWorkException catch (e) {
        if (mounted) widget.logs.add('已过滤文章作品：${e.message}');
        return null;
      } catch (e) {
        if (mounted) {
          widget.logs.add('作品解析失败：${_friendlyError(e)}');
        }
        return null;
      }
      if (!mounted) return null;
    }

    if (result.items.isEmpty) {
      widget.logs.add('该作品未捕获到可下载资源');
      return WorkDetailSelection(
        state: WorkSelectionState.none,
        parsedResult: result,
      );
    }

    if (result.isImagePost) {
      // 中层全选 -> 底层必须全选；未选 -> 全不选；部分 -> 恢复已选资源。
      // 不能传 null，否则底层会使用自己的记忆覆盖中层选择。
      final initialUrls = work.selectionState == WorkSelectionState.all
          ? result.items.map((item) => item.url).toSet()
          : work.selectedResourceUrls;
      final selected = await ImagePreviewSheet.show(
        context,
        items: result.items,
        headers: _mediaHeaders,
        nested: true,
        initialSelectedUrls: initialUrls,
        memoryScope: bottomScope,
      );
      if (!mounted) return null;
      if (selected == null) {
        // 系统返回：保持原状态，仅缓存解析结果
        return WorkDetailSelection(
          state: work.selectionState,
          selectedResources: work.selectedResources,
          parsedResult: result,
        );
      }
      final state = selected.isEmpty
          ? WorkSelectionState.none
          : (selected.length >= result.items.length
                ? WorkSelectionState.all
                : WorkSelectionState.partial);
      widget.logs.add('已选择 ${selected.length}/${result.items.length} 个资源');
      return WorkDetailSelection(
        state: state,
        selectedResources: selected,
        parsedResult: result,
      );
    }

    // 普通视频：点按选择单个画质档位，底部“返回”确认
    // 必须先按全局设置过滤并排序，再解析初始档位，避免初始项被过滤后回落到最高画质
    final tiers = VideoQualityUtils.displayTiers(result.videoItems);
    final currentItem = VideoQualityUtils.resolveChoice(
      work.qualityChoice,
      tiers,
    );
    final picked = await VideoQualitySheet.showSelect(
      context,
      tiers,
      initialItem: currentItem,
    );
    if (!mounted) return null;
    if (picked == null) {
      // 系统返回：保持原画质选择，仅缓存解析结果
      return WorkDetailSelection(
        state: work.selectionState,
        selectedResources: work.selectedResources,
        qualityChoice: work.qualityChoice,
        parsedResult: result,
      );
    }
    final choice = VideoQualityUtils.classifyChoice(tiers, picked);
    final qualityText = picked.resolutionLabel.isNotEmpty
        ? picked.resolutionLabel
        : (picked.resolution ?? picked.gearName ?? '默认画质');
    widget.logs.add('已选择 $qualityText（${picked.formattedSize}）');
    return WorkDetailSelection(
      // 特定档位表示只选了资源中的一档 -> 中层显示部分选择虚线；
      // 最高/最低档位是该作品的代表选择 -> 全选。
      state: choice.level == WorkVideoQualityLevel.specific
          ? WorkSelectionState.partial
          : WorkSelectionState.all,
      selectedResources: [picked],
      qualityChoice: choice,
      parsedResult: result,
    );
  }

  /// 生成历史记录的媒体摘要
  String _mediaSummaryFor(SingleWorkResult? parsed, WorkMediaKind kind) {
    if (parsed == null) {
      return kind == WorkMediaKind.image ? '图集/文案' : '视频/文案';
    }
    final tags = <String>[];
    if (parsed.videoCount > 0) {
      tags.add(parsed.isImagePost ? '实况' : '视频');
    }
    if (parsed.imageCount > 0) tags.add('图集');
    if (parsed.audioCount > 0) tags.add('音频');
    tags.add('文案');
    return tags.join('/');
  }

  /// 画质模式中文文案
  String _qualityLabel(BatchVideoQualityMode mode) {
    switch (mode) {
      case BatchVideoQualityMode.highest:
        return '最高画质';
      case BatchVideoQualityMode.lowest:
        return '最低画质';
      case BatchVideoQualityMode.mixed:
        return '混合画质';
    }
  }

  /// 根据作品类型弹出对应选择面板，返回用户选中的资源
  Future<List<MediaItem>?> _chooseItems(SniffResult result) async {
    if (result.isImagePost) {
      // 图文/实况图集：网格预览并勾选
      return ImagePreviewSheet.show(
        context,
        items: result.items,
        headers: _mediaHeaders,
        memoryScope: SaveMemoryScope.singleBottom,
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

  /// 刷新批量保存进度（作品级）
  void _updateBatchSaveProgress(int current, int total, String message) {
    if (!mounted) return;
    final prefix = message.startsWith('正在准备') ? '正在准备' : '正在保存';
    widget.logs.upsertLast(prefix, message);
    final overall = total == 0 ? 0.0 : current / total;
    _downloadProgress.value = overall.clamp(0.0, 1.0).toDouble();
  }

  /// 刷新批量下载进度（仅驱动局部进度条更新，避免触发整体界面重绘）
  void _updateBatchProgress(int current, int total, double itemProgress) {
    final percent = (itemProgress * 100).round();
    final key = '$current/$total/$percent';
    if (!mounted || key == _lastProgressKey) return;
    _lastProgressKey = key;

    // 总进度 = 已完成项 + 当前项进度
    final overall = total == 0 ? 0.0 : ((current - 1) + itemProgress) / total;
    widget.logs.upsertLast('正在下载第', '正在下载第 $current/$total 个资源（$percent%）...');
    _downloadProgress.value = overall.clamp(0.0, 1.0).toDouble();
  }

  /// 把异常转换成简短的中文提示
  String _friendlyError(Object error) {
    if (error is ArticleWorkException) {
      return error.message;
    }
    if (error is TimeoutException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;
      return '捕获超时，请检查链接是否有效后重试';
    }
    if (error is DioException && error.response?.statusCode == 403) {
      return '视频服务器拒绝了请求（403），请稍后重试';
    }
    return error.toString().replaceFirst(
      RegExp(r'^(Exception|Bad state|FormatException): '),
      '',
    );
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
                    color: colorScheme.primary.withValues(
                      alpha: isDark ? 0.35 : 0.25,
                    ),
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
  const _LoginPromptBanner({required this.loggedIn, this.onTapLogin});

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
        final iconColor = isDark
            ? const Color(0xFFFFB0C8)
            : theme.colorScheme.primary;
        final textColor = isDark
            ? const Color(0xFFECE0E2)
            : theme.colorScheme.onSurface;

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

/// 主页作品补抓代理：把解析页的补抓逻辑注入顶层保存器
class _HomeWorksDelegate implements IUserHomeBatchDelegate {
  _HomeWorksDelegate(this._extract);

  final Future<List<SaveWorkItem>> Function(String secUid) _extract;

  @override
  Future<List<SaveWorkItem>> extractWorks(String secUid) => _extract(secUid);
}
