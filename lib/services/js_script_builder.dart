library;

/// 注入式捕获脚本：支持重复注入，跨注入共享状态，兼容图文/实况图/普通视频。
///
/// 脚本按职责切片存放在 script/douyin/chunk，此处仅按原始顺序拼接；
/// 切片必须逐字节等价，任何顺序或空白改动都会改变注入行为。
import 'script/douyin/chunk/js_state_header.dart';
import 'script/douyin/chunk/js_logging.dart';
import 'script/douyin/chunk/js_login_probe.dart';
import 'script/douyin/chunk/js_aweme_ids.dart';
import 'script/douyin/chunk/js_media_url.dart';
import 'script/douyin/chunk/js_media_collect.dart';
import 'script/douyin/chunk/js_title_cover.dart';
import 'script/douyin/chunk/js_report.dart';
import 'script/douyin/chunk/js_network_hook.dart';
import 'script/douyin/chunk/js_scan_engine.dart';
import 'script/douyin/chunk/js_home_collect.dart';
import 'script/douyin/chunk/js_profile_extract.dart';
import 'script/douyin/chunk/js_home_dispatch.dart';
import 'script/douyin/chunk/js_bootstrap.dart';

/// 拼接后的完整注入脚本。
const String kDouyinSniffJs =
    '$jsStateHeader'
    '$jsLogging'
    '$jsLoginProbe'
    '$jsAwemeIds'
    '$jsMediaUrl'
    '$jsMediaCollect'
    '$jsTitleCover'
    '$jsReport'
    '$jsNetworkHook'
    '$jsScanEngine'
    '$jsHomeCollect'
    '$jsProfileExtract'
    '$jsHomeDispatch'
    '$jsBootstrap';
