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
import '../utils/save_page_debug_store.dart';
import '../utils/author_folder_name.dart';
import '../utils/home_save_path.dart';
import '../utils/url_parser.dart';
import 'batch_work/work_batch_saver.dart';
import 'douyin_sniffer.dart';
import 'history/album_locator.dart';
import 'video_downloader.dart';

part 'bridge/parse/parse_handler.dart';

part 'bridge/parse/parse_works_handler.dart';

part 'bridge/save/save_works_handler.dart';

part 'bridge/save/save_home_handler.dart';

part 'bridge/download/download_handler.dart';

part 'bridge/log/log_handler.dart';

part 'bridge/system/cancel_handler.dart';

part 'bridge/system/eval_handler.dart';

part 'bridge/system/quality_handler.dart';

part 'bridge/history/history_query_handler.dart';

part 'bridge/history/history_scan_handler.dart';

part 'bridge/history/history_open_handler.dart';

part 'bridge/history/history_clear_handler.dart';

part 'bridge/system/mock_login_handler.dart';

part 'bridge/media/display_handler.dart';

part 'bridge/media/thumbnail_handler.dart';

part 'bridge/verify/verify_covers_handler.dart';

part 'bridge/verify/verify_titles_handler.dart';

part 'bridge/parse/parse_profile_handler.dart';

part 'bridge/verify/verify_profile_handler.dart';

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
  UserHomeProfile? _lastUserHomeProfile;
  String? _lastRawInput;
  String? _lastParsedUrl;
  CancelToken? _activeDownloadToken;

  /// 供单元测试注入模拟的主页捕获结果
  @visibleForTesting
  void setLastUserHomeResultForTesting(UserHomeResult result) {
    _lastUserHomeResult = result;
    _lastUserHomeProfile = result.profile;
  }

  /// 供单元测试注入模拟的主页作者基础信息
  @visibleForTesting
  void setLastUserHomeProfileForTesting(UserHomeProfile profile) {
    _lastUserHomeProfile = profile;
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
      } else if (path == '/api/parse-works' && request.method == 'POST') {
        await _handleParseWorks(request);
      } else if (path == '/api/save/works' && request.method == 'POST') {
        await _handleSaveWorks(request);
      } else if (path == '/api/save/home' && request.method == 'POST') {
        await _handleSaveHome(request);
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
      } else if (path == '/api/save-debug' && request.method == 'GET') {
        _sendJson(request, HttpStatus.ok, {
          'snapshot': SavePageDebugStore.snapshot ?? {'layer': 'none'},
        });
      } else if (path == '/api/history' && request.method == 'GET') {
        await _handleGetHistory(request);
      } else if (path == '/api/history/scan' && request.method == 'POST') {
        await _handleScanHistory(request);
      } else if (path == '/api/history/open' && request.method == 'POST') {
        await _handleOpenHistory(request);
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
      } else if (path == '/api/parse-profile' && request.method == 'POST') {
        await _handleParseProfile(request);
      } else if (path == '/api/verify/home-profile' && request.method == 'POST') {
        await _handleVerifyHomeProfile(request);
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

  /// 将画质字符串转换为批量保存模式
  BatchVideoQualityMode _qualityModeFrom(String? raw) {
    if (raw == 'lowest') return BatchVideoQualityMode.lowest;
    if (raw == 'mixed') return BatchVideoQualityMode.mixed;
    return BatchVideoQualityMode.highest;
  }

  Map<String, dynamic> _serializeWorkSaveResult(WorkSaveResult result) {
    return {
      'url': result.url,
      'success': result.success,
      'savedTypes': result.savedTypes.map((type) => type.name).toList(),
      'savedBaseName': result.savedBaseName,
      if (result.error != null) 'error': result.error,
    };
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
  /// 169 方案：主页作者头像与昵称基准对照表 (PLAN_56)
  static const List<Map<String, String>> kReference169Profiles = [
    {
      'nickname': '宁采君',
      'secUid': '8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04',
      'url': 'https://www.douyin.com/user/MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04?from_tab_name=main',
      'avatarUri': 'tos-cn-i-0813_osIMyzAvEiznnjAA6W1AXBRCSIQHN0AfgASiCe',
      'avatarFile': 'sources/169/profile/宁采君.jpeg',
    },
    {
      'nickname': '药厂人家',
      'secUid': 'ZdOvEbWjf4xvbLcbhITo_77_pWvO71pLZ7sUyVlwcIM',
      'url': 'https://www.douyin.com/user/MS4wLjABAAAAZdOvEbWjf4xvbLcbhITo_77_pWvO71pLZ7sUyVlwcIM?from_tab_name=main',
      'avatarUri': 'tos-cn-i-0813c001_oMBlAnRE8AeJAJCbAgOwMCkElD948APVDIfCAJ',
      'avatarFile': 'sources/169/profile/药厂人家.jpeg',
    },
    {
      'nickname': '腿祖宗.Ann',
      'secUid': 'bsKQ1oJmO2lPuWeLbiBuEGZ4Wycv-dOODWb1p625oY7IPuPmdIyqsVmzsQ-FkDIM',
      'url': 'https://www.douyin.com/user/MS4wLjABAAAAbsKQ1oJmO2lPuWeLbiBuEGZ4Wycv-dOODWb1p625oY7IPuPmdIyqsVmzsQ-FkDIM?from_tab_name=main&vid=7695021109306389211',
      'avatarUri': 'tos-cn-avt-0015_9fff5b3e30b9237b74949f2e8d3da829',
      'avatarFile': 'sources/169/profile/腿祖宗.Ann.jpeg',
    },
  ];
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
