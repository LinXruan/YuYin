import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../../../app_info.dart';
import '../../../models/history_item.dart';
import '../../../models/media_item.dart';
import '../../../utils/settings/display_mode_service.dart';
import '../../../utils/settings/download_settings_store.dart';
import '../../../utils/history/history_store.dart';
import '../../../utils/debug/log_controller.dart';
import '../../../utils/savelocation/save_location_store.dart';
import '../../../utils/debug/save_page_debug_store.dart';
import '../../../utils/url_parser.dart';
import '../../sniffer/facade/douyin_sniffer.dart';
import '../../media/video_downloader.dart';
import '../handler/download_handler.dart';
import '../handler/history_handler.dart';
import '../handler/log_handler.dart';
import '../handler/media_handler.dart';
import '../handler/save_handler.dart';
import '../handler/selection_handler.dart';
import '../handler/system_handler.dart';
import '../handler/verify_handler.dart';

part '../parse/parse_handler.dart';

part '../parse/status_handler.dart';

part '../parse/parse_works_handler.dart';

part '../parse/parse_homes_handler.dart';

part '../parse/parse_profile_handler.dart';

part 'agent_router.dart';

part '../protocol/bridge_serializers.dart';

part '../protocol/bridge_protocol.dart';

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
  SniffResult? lastResult;
  UserHomeResult? lastUserHomeResult;
  UserHomeProfile? lastUserHomeProfile;
  String? lastRawInput;
  String? lastParsedUrl;
  CancelToken? activeDownloadToken;

  /// 端点处理器：门面只负责生命周期与分发
  late final SystemHandler system = SystemHandler(this);
  late final LogHandler logHandler = LogHandler(this);
  late final MediaHandler mediaHandler = MediaHandler(this);
  late final HistoryHandler historyHandler = HistoryHandler(this);
  late final VerifyHandler verifyHandler = VerifyHandler(this);
  late final DownloadHandler downloadHandler = DownloadHandler(this);
  late final SaveHandler saveHandler = SaveHandler(this);
  late final SelectionHandler selectionHandler = SelectionHandler(this);

  /// 供单元测试注入模拟的主页捕获结果
  @visibleForTesting
  void setLastUserHomeResultForTesting(UserHomeResult result) {
    lastUserHomeResult = result;
    lastUserHomeProfile = result.profile;
  }

  /// 供单元测试注入模拟的主页作者基础信息
  @visibleForTesting
  void setLastUserHomeProfileForTesting(UserHomeProfile profile) {
    lastUserHomeProfile = profile;
  }

  /// 服务实际绑定的端口（未启动时为 null）
  int? get boundPort => _server?.port;

  /// 启动本地 HTTP 自动化服务：仅 Debug 构建、仅环回地址
  Future<void> start() async {
    if (!kDebugMode) {
      debugPrint('[AgentBridge] 非 Debug 构建，跳过本地自动化控制台');
      return;
    }
    if (_server != null) return;
    try {
      _server = await HttpServer.bind(InternetAddress.loopbackIPv4, port);
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
    activeDownloadToken?.cancel('服务已停止');
    activeDownloadToken = null;
    await _server?.close(force: true);
    _server = null;
    debugPrint('[AgentBridge] 自动化控制台已关闭');
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
}