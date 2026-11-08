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
      'lastUserHomeResult': _lastUserHomeResult?.toMap(),
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
        logs.add('[主页] 成功捕获作者【$author】全部作品链接共 ${homeResult.count} 条$tagText');
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
