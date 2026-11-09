import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../app_info.dart';
import '../models/history_item.dart';
import '../models/media_item.dart';
import '../utils/display_mode_service.dart';
import '../utils/download_settings_store.dart';
import '../utils/file_name_formatter.dart';
import '../utils/history_store.dart';
import '../utils/history_thumbnail_cache.dart';
import '../utils/log_controller.dart';
import '../utils/login_state_store.dart';
import '../utils/save_location_store.dart';
import '../utils/url_parser.dart';
import 'douyin_sniffer.dart';
import 'video_downloader.dart';

/// 专为 Agent 自动化操控设计的本地无头调试服务（仅在 Debug 模式下启用）
class AgentAutomationServer {
  AgentAutomationServer({
    this.sniffer,
    this.downloader,
    required this.logs,
    required this.busy,
    required this.loggedIn,
    this.port = 9527,
  });

  final DouyinSniffer? sniffer;
  final VideoDownloader? downloader;
  final LogController logs;
  final ValueNotifier<bool> busy;
  final ValueNotifier<bool> loggedIn;
  final int port;

  HttpServer? _server;
  SniffResult? _lastResult;
  UserHomeResult? _lastUserHomeResult;
  String? _lastRawInput;
  String? _lastParsedUrl;
  CancelToken? _activeDownloadToken;

  /// 供单元测试注入模拟的主页捕获结果
  @visibleForTesting
  void setLastUserHomeResultForTesting(UserHomeResult result) {
    _lastUserHomeResult = result;
  }

  /// 启动本地 HTTP 自动化服务
  Future<void> start() async {
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
      debugPrint('[AgentBridge] 本地自动化控制台已就绪: port=$port (PID=$pid)');
      _server!.listen(_handleRequest, onError: (Object err) {
        debugPrint('[AgentBridge] 接收请求异常: $err');
      });
    } catch (e) {
      debugPrint('[AgentBridge] 绑定端口 $port 失败: $e');
    }
  }

  /// 停止服务并释放端口
  Future<void> stop() async {
    _activeDownloadToken?.cancel('服务已停止');
    _activeDownloadToken = null;
    await _server?.close(force: true);
    _server = null;
    debugPrint('[AgentBridge] 自动化控制台已关闭');
  }

  /// 请求分发路由器
  Future<void> _handleRequest(HttpRequest request) async {
    // 跨域支持与编码设置
    request.response.headers
      ..set('Access-Control-Allow-Origin', '*')
      ..set('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
      ..set('Access-Control-Allow-Headers', 'Content-Type')
      ..set('Content-Type', 'application/json; charset=utf-8');

    if (request.method == 'OPTIONS') {
      request.response.statusCode = HttpStatus.ok;
      await request.response.close();
      return;
    }

    final path = request.uri.path;
    try {
      if (path == '/api/status' && request.method == 'GET') {
        await _handleStatus(request);
      } else if (path == '/api/parse' && request.method == 'POST') {
        await _handleParse(request);
      } else if (path == '/api/download' && request.method == 'POST') {
        await _handleDownload(request);
      } else if (path == '/api/logs' && request.method == 'GET') {
        await _handleGetLogs(request);
      } else if (path == '/api/logs/clear' && request.method == 'POST') {
        await _handleClearLogs(request);
      } else if (path == '/api/cancel' && request.method == 'POST') {
        await _handleCancel(request);
      } else if (path == '/api/eval' && request.method == 'POST') {
        await _handleEval(request);
      } else if (path == '/api/settings/quality' && request.method == 'POST') {
        await _handleSetQualitySetting(request);
      } else if (path == '/api/history' && request.method == 'GET') {
        await _handleGetHistory(request);
      } else if (path == '/api/history/clear' && request.method == 'POST') {
        await _handleClearHistory(request);
      } else if (path == '/api/login/mock' && request.method == 'POST') {
        await _handleMockLogin(request);
      } else if (path == '/api/display' && request.method == 'GET') {
        await _handleGetDisplay(request);
      } else if (path == '/api/thumbnails' && request.method == 'GET') {
        await _handleGetThumbnails(request);
      } else if (path == '/api/thumbnails/clear' && request.method == 'POST') {
        await _handleClearThumbnails(request);
      } else if (path == '/api/thumbnails/preload' && request.method == 'POST') {
        await _handlePreloadThumbnails(request);
      } else if (path == '/api/verify/home-covers' && request.method == 'POST') {
        await _handleVerifyHomeCovers(request);
      } else if (path == '/api/verify/home-titles' && request.method == 'POST') {
        await _handleVerifyHomeTitles(request);
      } else {
        _sendJson(
          request,
          HttpStatus.notFound,
          {'error': '未找到路由: $path', 'code': 404},
        );
      }
    } catch (e, stack) {
      debugPrint('[AgentBridge] 处理请求 $path 异常: $e\n$stack');
      _sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': e.toString(), 'code': 500},
      );
    }
  }

  /// GET /api/status：查询当前应用状态
  Future<void> _handleStatus(HttpRequest request) async {
    final result = _lastResult;
    final Map<String, dynamic>? lastResultJson;
    if (result != null) {
      lastResultJson = {
        'title': result.title,
        'desc': result.desc,
        'isImagePost': result.isImagePost,
        'totalItems': result.items.length,
        'imageCount': result.imageCount,
        'videoCount': result.videoCount,
        'audioCount': result.audioCount,
        'items': _serializeItems(result.items),
      };
    } else {
      lastResultJson = null;
    }

    _sendJson(request, HttpStatus.ok, {
      'app': appName,
      'version': appVersion,
      'busy': busy.value,
      'loggedIn': loggedIn.value,
      'snifferLoggedIn': sniffer?.isUserLoggedIn ?? false,
      'hasParsedResult': result != null,
      'lastInput': _lastRawInput,
      'lastResult': lastResultJson,
      'lastUserHomeResult': _lastUserHomeResult == null
          ? null
          : {
              'secUid': _lastUserHomeResult!.secUid,
              'nickname': _lastUserHomeResult!.nickname,
              'count': _lastUserHomeResult!.count,
              'tabCount': _lastUserHomeResult!.tabCount,
              'worksTotalTag': _lastUserHomeResult!.worksTotalTag,
              'coversCount': _lastUserHomeResult!.coversCount,
              'hasCovers': _lastUserHomeResult!.workCovers.isNotEmpty,
              'titlesCount': _lastUserHomeResult!.titlesCount,
              'hasTitles': _lastUserHomeResult!.workTitles.isNotEmpty,
            },
      'logsCount': logs.logs.length,
      'downloadSettings': {
        'onlyHighestQualityPerResolution':
            DownloadSettingsStore.onlyHighestQualityPerResolution,
        'isSaveLocationDefault': SaveLocationStore.isAllDefault,
      },
      'display': {
        'activeRefreshRate': DisplayModeService.activeRefreshRate,
        'maxRefreshRate': DisplayModeService.maxRefreshRate,
        'isHighRefreshRate': DisplayModeService.isHighRefreshRate,
      },
    });
  }

  /// POST /api/parse：执行作品捕获解析
  Future<void> _handleParse(HttpRequest request) async {
    if (busy.value) {
      _sendJson(
        request,
        HttpStatus.conflict,
        {'error': '应用正在执行其他任务，请稍候', 'code': 409},
      );
      return;
    }

    final body = await _readJsonBody(request);
    final text = body['text']?.toString() ?? body['url']?.toString() ?? '';
    if (text.trim().isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '缺少必要参数: text 或 url', 'code': 400},
      );
      return;
    }

    final url = UrlParser.extractDouyinUrl(text);
    if (url == null) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '未识别到有效的抖音链接', 'code': 400, 'raw': text},
      );
      return;
    }

    if (UrlParser.isUserHomeUrl(url)) {
      if (!loggedIn.value) {
        logs.reset('正在提取短链...');
        logs.add('请登录再进行主页链接解析');
        _sendJson(
          request,
          HttpStatus.forbidden,
          {'error': '请登录再进行主页链接解析', 'code': 403, 'isUserHome': true},
        );
        return;
      }

      busy.value = true;
      logs.reset('正在提取短链...');
      logs.add('正在捕获作者主页作品链接...');
      try {
        final currentSniffer = sniffer;
        if (currentSniffer == null) {
          throw StateError('捕获服务未初始化');
        }
        final homeResult = await currentSniffer.sniffUserHomeUrl(url);
        _lastUserHomeResult = homeResult;
        _lastRawInput = text;
        _lastParsedUrl = url;
        final author =
            homeResult.nickname.isNotEmpty ? homeResult.nickname : '未知作者';
        final tagText = (homeResult.tabCount != null && homeResult.tabCount! > 0)
            ? '，作品总数标注: ${homeResult.tabCount} 个'
            : '';
        final coverText = homeResult.coversCount > 0
            ? ' (已关联封面: ${homeResult.coversCount} 条)'
            : '';
        logs.add('[主页] 成功捕获作者【$author】全部作品链接共 ${homeResult.count} 条$tagText$coverText');
        logs.add('主页作品捕获完成');
        _sendJson(request, HttpStatus.ok, {
          'type': 'user_home',
          'result': homeResult.toMap(),
          'logs': logs.logs,
        });
      } catch (e) {
        logs.add('主页解析失败: $e');
        _sendJson(
          request,
          HttpStatus.internalServerError,
          {'error': '$e', 'code': 500},
        );
      } finally {
        busy.value = false;
      }
      return;
    }

    busy.value = true;
    logs.reset('正在提取短链...');
    logs.add('正在解析作品...');

    try {
      final currentSniffer = sniffer;
      if (currentSniffer == null) {
        throw StateError('捕获服务未初始化');
      }
      final result = await currentSniffer.sniffVideoUrl(url);
      _lastResult = result;
      _lastRawInput = text;
      _lastParsedUrl = url;

      // 成功解析后自动计入历史记录
      if (result.items.isNotEmpty) {
        String? coverUrl = (result.coverUrl?.trim().isNotEmpty ?? false)
            ? result.coverUrl!.trim()
            : null;
        if (coverUrl == null) {
        for (final it in result.items) {
          if (it.type == MediaType.image && it.url.isNotEmpty) {
            coverUrl = it.url;
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

        final fullDesc = (result.desc?.trim().isNotEmpty ?? false)
            ? result.desc!.trim()
            : (result.title?.trim().isNotEmpty ?? false
                ? result.title!.trim()
                : text);

        HistoryStore.addRecord(
          HistoryItem(
            id: url,
            url: url,
            rawInput: text,
            fullDesc: fullDesc,
            title: result.title,
            coverUrl: coverUrl,
            isImagePost: result.isImagePost,
            mediaSummary: summaryTags.join('/'),
            itemCount: result.items.length,
          ),
        );
      }

      _sendJson(request, HttpStatus.ok, {
        'success': true,
        'title': result.title,
        'desc': result.desc,
        'isImagePost': result.isImagePost,
        'totalItems': result.items.length,
        'imageCount': result.imageCount,
        'videoCount': result.videoCount,
        'audioCount': result.audioCount,
        'items': _serializeItems(result.items),
      });
    } catch (e) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '解析失败: $e', 'code': 400},
      );
    } finally {
      busy.value = false;
    }
  }

  /// POST /api/download：执行资源下载与落盘
  Future<void> _handleDownload(HttpRequest request) async {
    final result = _lastResult;
    if (result == null || result.items.isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未成功解析作品，无可用下载资源', 'code': 400},
      );
      return;
    }
    if (busy.value) {
      _sendJson(
        request,
        HttpStatus.conflict,
        {'error': '当前有任务正在执行', 'code': 409},
      );
      return;
    }

    final body = await _readJsonBody(request);
    final dynamic rawIndices = body['indices'];
    final List<MediaItem> selected;

    if (rawIndices == null || rawIndices == 'all') {
      selected = result.items;
    } else if (rawIndices is List) {
      selected = <MediaItem>[];
      for (final idx in rawIndices) {
        if (idx is int && idx >= 0 && idx < result.items.length) {
          selected.add(result.items[idx]);
        }
      }
    } else if (rawIndices is int) {
      selected = <MediaItem>[];
      if (rawIndices >= 0 && rawIndices < result.items.length) {
        selected.add(result.items[rawIndices]);
      }
    } else if (rawIndices is String && int.tryParse(rawIndices) != null) {
      final idx = int.parse(rawIndices);
      selected = <MediaItem>[];
      if (idx >= 0 && idx < result.items.length) {
        selected.add(result.items[idx]);
      }
    } else {
      selected = result.items;
    }

    if (selected.isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '选中的资源列表为空', 'code': 400},
      );
      return;
    }

    busy.value = true;
    final token = CancelToken();
    _activeDownloadToken = token;

    final candidateDesc = (result.desc?.trim().isNotEmpty ?? false)
        ? result.desc!.trim()
        : UrlParser.extractShareText(_lastRawInput ?? '');

    try {
      final currentDownloader = downloader;
      if (currentDownloader == null) {
        throw StateError('下载服务未初始化');
      }
      logs.add('开始下载 ${selected.length} 个选中资源...');
      final savedTypes = await currentDownloader.downloadItems(
        selected,
        cookie: result.cookie,
        baseTitle: candidateDesc,
        cancelToken: token,
        onProgress: (current, total, progress) {
          // 下载进度内部更新
        },
      );

      if (savedTypes.isNotEmpty && _lastParsedUrl != null) {
        HistoryStore.markSaved(_lastParsedUrl!, true);
      }

      // 计算保存路径展示
      final savedLocations = <String, String>{};
      for (final type in savedTypes) {
        final path = SaveLocationStore.getDisplayPath(type);
        savedLocations[type.name] = path;
        logs.add('${type.label}已保存到$path');
      }

      // 生成预期的最终文件名列表供 Agent 校验
      final expectedFiles = <String>[];
      for (var i = 0; i < selected.length; i++) {
        expectedFiles.add(
          FileNameFormatter.formatFileName(
            item: selected[i],
            allItems: selected,
            currentIndex: i,
            rawTitleOrDesc: candidateDesc,
          ),
        );
      }

      _sendJson(request, HttpStatus.ok, {
        'success': true,
        'downloadedCount': selected.length,
        'savedTypes': savedTypes.map((t) => t.name).toList(),
        'savedLocations': savedLocations,
        'expectedFiles': expectedFiles,
      });
    } catch (e) {
      _sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': '下载失败: $e', 'code': 500},
      );
    } finally {
      _activeDownloadToken = null;
      busy.value = false;
    }
  }

  /// GET /api/logs：获取当前全量日志
  Future<void> _handleGetLogs(HttpRequest request) async {
    _sendJson(request, HttpStatus.ok, {
      'count': logs.logs.length,
      'logs': logs.logs,
    });
  }

  /// POST /api/logs/clear：清空日志
  Future<void> _handleClearLogs(HttpRequest request) async {
    logs.clear();
    _sendJson(request, HttpStatus.ok, {'success': true});
  }

  /// POST /api/cancel：取消当前进行中的任务
  Future<void> _handleCancel(HttpRequest request) async {
    sniffer?.cancelActiveTask();
    _activeDownloadToken?.cancel('Agent 指令取消');
    _activeDownloadToken = null;
    busy.value = false;
    logs.add('已取消解析');
    _sendJson(request, HttpStatus.ok, {'success': true});
  }

  /// POST /api/eval：向捕获 WebView 注入并执行 JS 脚本
  Future<void> _handleEval(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final script = body['script']?.toString();
    if (script == null || script.trim().isEmpty) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '缺少 script 参数', 'code': 400},
      );
      return;
    }

    if (sniffer == null) {
      _sendJson(
        request,
        HttpStatus.serviceUnavailable,
        {'error': 'Sniffer 服务未初始化', 'code': 503},
      );
      return;
    }

    try {
      final rawResult =
          await sniffer!.controller.runJavaScriptReturningResult(script);
      _sendJson(request, HttpStatus.ok, {
        'success': true,
        'result': rawResult.toString(),
      });
    } catch (e) {
      _sendJson(
        request,
        HttpStatus.internalServerError,
        {'error': 'JS 执行失败: $e', 'code': 500},
      );
    }
  }

  /// POST /api/settings/quality：切换“仅显示同分辨率下最高画质”开关
  Future<void> _handleSetQualitySetting(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final enabled = body['onlyHighestQualityPerResolution'];
    if (enabled is! bool) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {
          'error': '缺少必要布尔参数: onlyHighestQualityPerResolution',
          'code': 400,
        },
      );
      return;
    }

    await DownloadSettingsStore.setOnlyHighestQualityPerResolution(enabled);
    _sendJson(request, HttpStatus.ok, {
      'success': true,
      'onlyHighestQualityPerResolution':
          DownloadSettingsStore.onlyHighestQualityPerResolution,
    });
  }

  /// GET /api/history：获取当前全部历史记录或按关键字搜索
  Future<void> _handleGetHistory(HttpRequest request) async {
    final query = request.uri.queryParameters['q'];
    final records = query != null && query.trim().isNotEmpty
        ? HistoryStore.search(query.trim())
        : HistoryStore.records;

    _sendJson(request, HttpStatus.ok, {
      'count': records.length,
      'records': records.map((r) => r.toJson()).toList(),
    });
  }

  /// POST /api/history/clear：清空历史记录
  Future<void> _handleClearHistory(HttpRequest request) async {
    await HistoryStore.clearAll();
    _sendJson(request, HttpStatus.ok, {
      'success': true,
      'message': '历史记录已清空',
    });
  }

  /// POST /api/login/mock：动态模拟设置本地登录状态（用于自动化测试）
  Future<void> _handleMockLogin(HttpRequest request) async {
    final body = await _readJsonBody(request);
    final mockLoggedIn = body['loggedIn'] == true;
    if (mockLoggedIn) {
      await LoginStateStore.markLoggedIn();
      loggedIn.value = true;
      logs.add('[AgentBridge] 已模拟设置为登录状态 (loggedIn=true)');
    } else {
      await LoginStateStore.clearLogin();
      loggedIn.value = false;
      logs.add('[AgentBridge] 已清除登录状态 (loggedIn=false)');
    }
    _sendJson(request, HttpStatus.ok, {
      'success': true,
      'loggedIn': loggedIn.value,
      'message': '登录状态已更新为: ${loggedIn.value}',
    });
  }

  List<Map<String, dynamic>> _serializeItems(List<MediaItem> items) {
    return items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      return {
        'index': i,
        'type': item.type.name,
        'url': item.url,
        'resolution': item.resolution,
        'resolutionLabel': item.resolutionLabel,
        'dataSize': item.dataSize,
        'formattedSize': item.formattedSize,
        'bitRate': item.bitRate,
        'formattedBitRate': item.formattedBitRate,
        'gearName': item.gearName,
      };
    }).toList();
  }

  Future<void> _handleGetDisplay(HttpRequest request) async {
    _sendJson(request, HttpStatus.ok, {
      'activeRefreshRate': DisplayModeService.activeRefreshRate,
      'maxRefreshRate': DisplayModeService.maxRefreshRate,
      'isHighRefreshRate': DisplayModeService.isHighRefreshRate,
      'width': DisplayModeService.displayWidth,
      'height': DisplayModeService.displayHeight,
      'supportedModesCount': DisplayModeService.supportedModesCount,
    });
  }

  /// GET /api/thumbnails：查询本地缩略图离线缓存状态
  Future<void> _handleGetThumbnails(HttpRequest request) async {
    final stats = await HistoryThumbnailCache.getStats();
    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'stats': stats,
    });
  }

  /// POST /api/thumbnails/clear：清空本地缩略图缓存
  Future<void> _handleClearThumbnails(HttpRequest request) async {
    await HistoryThumbnailCache.clearCache();
    logs.add('[缩略图] 本地缩略图离线缓存已完全清空');
    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'message': '缩略图缓存已清空',
    });
  }

  /// POST /api/thumbnails/preload：对所有未缓存缩略图的历史记录执行后台离线缓存
  Future<void> _handlePreloadThumbnails(HttpRequest request) async {
    final records = HistoryStore.records;
    int triggered = 0;
    for (final item in records) {
      if (item.coverUrl != null && item.coverUrl!.isNotEmpty) {
        if (HistoryThumbnailCache.getCachedFileSync(item.id) == null) {
          HistoryThumbnailCache.cacheThumbnail(item.id, item.coverUrl!);
          triggered++;
        }
      }
    }
    logs.add('[缩略图] 已触发 $triggered 条历史记录的本地离线缓存预热');
    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'triggeredCount': triggered,
      'totalRecords': records.length,
    });
  }

  /// 167 真实主页作品与封面图片参照对照表 (仅用于 Debug 比对验证)
  static const Map<String, String> kReference167Map = {
    'https://www.douyin.com/note/7701683319334910554': '01.jpg',
    'https://www.douyin.com/video/7699742794776932454': '02.jpg',
    'https://www.douyin.com/video/7681695622663032794': '03.jpg',
    'https://www.douyin.com/video/7704664460653454153': '04.jpg',
    'https://www.douyin.com/note/7701331294467341211': '05.jpg',
    'https://www.douyin.com/note/7701270275615027622': '06.jpg',
    'https://www.douyin.com/note/7700845558298246502': '07.jpg',
    'https://www.douyin.com/note/7699169682201808818': '08.jpg',
    'https://www.douyin.com/note/7698651843623366906': '09.jpg',
    'https://www.douyin.com/article/7697159257049500763': '10.jpg',
    'https://www.douyin.com/video/7696450088373463451': '11.jpg',
    'https://www.douyin.com/note/7695431697895172234': '12.jpg',
    'https://www.douyin.com/video/7692078721939105499': '13.jpg',
    'https://www.douyin.com/video/7681983578297077897': '14.jpg',
    'https://www.douyin.com/note/7675935070243298907': '15.jpg',
  };

  /// POST /api/verify/home-covers：主页作品封面图捕获校验与比对（仅 Debug 版）
  Future<void> _handleVerifyHomeCovers(HttpRequest request) async {
    final homeResult = _lastUserHomeResult;
    if (homeResult == null) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未执行主页解析，请先调用 /api/parse 解析主页链接', 'code': 400},
      );
      return;
    }

    final covers = homeResult.workCovers;
    final details = <Map<String, dynamic>>[];
    int matchedCount = 0;

    int idx = 1;
    for (final entry in kReference167Map.entries) {
      final expectedUrl = entry.key;
      final refImg = entry.value;
      final expectedId = RegExp(r'\d{10,}').firstMatch(expectedUrl)?.group(0);

      // 支持精准匹配或按作品数字 ID 跨路由兼容匹配 (/video/ /note/ /article/)
      String? capturedCover = covers[expectedUrl];
      if (capturedCover == null && expectedId != null) {
        for (final item in covers.entries) {
          if (item.key.contains(expectedId)) {
            capturedCover = item.value;
            break;
          }
        }
      }

      final hasCover = capturedCover != null && capturedCover.isNotEmpty;
      final isHttpUrl = hasCover &&
          (capturedCover.startsWith('http://') ||
              capturedCover.startsWith('https://'));

      final matched = hasCover && isHttpUrl;
      if (matched) matchedCount++;

      details.add({
        'index': idx.toString().padLeft(2, '0'),
        'url': expectedUrl,
        'referenceImage': refImg,
        'hasCover': hasCover,
        'coverUrl': capturedCover ?? '',
        'matched': matched,
      });
      idx++;
    }

    final rate = kReference167Map.isEmpty
        ? 0.0
        : (matchedCount / kReference167Map.length);

    logs.add('[封面验证] 167 样本比对完成: 匹配 $matchedCount / ${kReference167Map.length} (${(rate * 100).toStringAsFixed(1)}%)');

    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'matchRate': rate,
      'totalExpected': kReference167Map.length,
      'capturedCount': homeResult.count,
      'coversCount': homeResult.coversCount,
      'matchedCount': matchedCount,
      'details': details,
    });
  }

  /// 168 真实主页作品与显示标题/文案参照对照表 (仅用于 Debug 比对验证)
  static const Map<String, String> kReference168TitlesMap = {
    'https://www.douyin.com/note/7701683319334910554': '所以我们撕下了邪典 折成千万',
    'https://www.douyin.com/video/7699742794776932454': '泰拉瑞亚二十万瞬伤！骑枪秒',
    'https://www.douyin.com/video/7681695622663032794': '泰拉瑞亚原版10万瞬伤装置',
    'https://www.douyin.com/video/7704664460653454153': '根本没有这样的车技',
    'https://www.douyin.com/note/7701331294467341211': '若是真英雄怎么会怕？#哈基米',
    'https://www.douyin.com/note/7701270275615027622': '好像回到了中学时代，那时候',
    'https://www.douyin.com/note/7700845558298246502': 'ai，我们来做个约定，我会遍',
    'https://www.douyin.com/note/7699169682201808818': '遗憾的是，人们往往在了解什',
    'https://www.douyin.com/note/7698651843623366906': '服下过期的药，期盼它能够治',
    'https://www.douyin.com/article/7697159257049500763': '文娱工作者离不开绿帽烂裤裆',
    'https://www.douyin.com/video/7696450088373463451': '人类历史的转折点，却无人问',
    'https://www.douyin.com/note/7695431697895172234': '遗憾的是多少年后，每一个少',
    'https://www.douyin.com/video/7692078721939105499': '何为第九艺术的魅力 #第九艺',
    'https://www.douyin.com/video/7681983578297077897': '1.4.5.8.卡地牢宝箱，145通用',
    'https://www.douyin.com/note/7675935070243298907': '我最害怕有小萝莉给我发语音',
  };

  /// POST /api/verify/home-titles：主页作品标题/文案捕获校验与比对（仅 Debug 版）
  Future<void> _handleVerifyHomeTitles(HttpRequest request) async {
    final homeResult = _lastUserHomeResult;
    if (homeResult == null) {
      _sendJson(
        request,
        HttpStatus.badRequest,
        {'error': '尚未执行主页解析，请先调用 /api/parse 解析主页链接', 'code': 400},
      );
      return;
    }

    final titles = homeResult.workTitles;
    final details = <Map<String, dynamic>>[];
    int matchedCount = 0;

    int idx = 1;
    for (final entry in kReference168TitlesMap.entries) {
      final expectedUrl = entry.key;
      final expectedKeyword = entry.value;
      final expectedId = RegExp(r'\d{10,}').firstMatch(expectedUrl)?.group(0);

      // 支持精准匹配或按作品数字 ID 跨路由兼容匹配 (/video/ /note/ /article/)
      String? capturedTitle = titles[expectedUrl];
      if (capturedTitle == null && expectedId != null) {
        for (final item in titles.entries) {
          if (item.key.contains(expectedId)) {
            capturedTitle = item.value;
            break;
          }
        }
      }

      final hasTitle = capturedTitle != null && capturedTitle.trim().isNotEmpty;
      // 判定匹配：由于卡片文案可能包含省略号，因此检查包含关系或前缀一致
      bool matched = false;
      if (hasTitle) {
        final cleanExpected = expectedKeyword.replaceAll('…', '').replaceAll('...', '').trim();
        final cleanCaptured = capturedTitle.replaceAll('…', '').replaceAll('...', '').trim();
        if (cleanCaptured.contains(cleanExpected) || cleanExpected.contains(cleanCaptured)) {
          matched = true;
        } else {
          final prefixLen = cleanExpected.length < 6 ? cleanExpected.length : 6;
          if (cleanCaptured.startsWith(cleanExpected.substring(0, prefixLen))) {
            matched = true;
          }
        }
      }

      if (matched) matchedCount++;

      final summary = capturedTitle == null
          ? ''
          : (capturedTitle.length > 20 ? '${capturedTitle.substring(0, 20)}...' : capturedTitle);

      details.add({
        'index': idx.toString().padLeft(2, '0'),
        'url': expectedUrl,
        'expectedTitle': expectedKeyword,
        'hasTitle': hasTitle,
        'title': capturedTitle ?? '',
        'titleSummary': summary,
        'matched': matched,
      });
      idx++;
    }

    final rate = kReference168TitlesMap.isEmpty
        ? 0.0
        : (matchedCount / kReference168TitlesMap.length);

    logs.add('[标题验证] 168 样本比对完成: 匹配 $matchedCount / ${kReference168TitlesMap.length} (${(rate * 100).toStringAsFixed(1)}%)');

    _sendJson(request, HttpStatus.ok, {
      'status': 'ok',
      'matchRate': rate,
      'totalExpected': kReference168TitlesMap.length,
      'capturedCount': homeResult.count,
      'titlesCount': homeResult.titlesCount,
      'matchedCount': matchedCount,
      'details': details,
    });
  }

  Future<Map<String, dynamic>> _readJsonBody(HttpRequest request) async {
    try {
      final content = await utf8.decodeStream(request);
      if (content.trim().isEmpty) return const {};
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      return const {};
    } catch (_) {
      return const {};
    }
  }

  void _sendJson(HttpRequest request, int statusCode, Map<String, dynamic> data) {
    request.response.statusCode = statusCode;
    request.response.write(jsonEncode(data));
    request.response.close();
  }
}
