import 'package:webview_flutter/webview_flutter.dart';

import '../script/sniffer_script_injector.dart';
import '../session/sniff_session.dart';

/// 单作品解析策略依赖的宿主能力契约。
///
/// 隔离策略对象与门面具体实现的耦合，仅暴露状态容器、控制句柄与生命周期信号。
abstract class SnifferSingleHost {
  /// 当前单作品任务的任务态会话
  SniffSession get session;

  /// 底层常驻 WebView 控制器
  WebViewController get controller;

  /// 脚本注入管理器
  SnifferScriptInjector get scriptInjector;

  /// 服务是否已释放
  bool get isDisposed;

  /// 当前是否已登录
  bool get snifferLoggedIn;

  /// 设置当前登录态
  set snifferLoggedIn(bool value);

  /// 登录态查询回调（主界面提供）
  bool Function()? get isLoggedIn;

  /// 内部诊断日志
  void logDiagnostic(String message);

  /// 用户可见日志
  void reportUserLog(String message);

  /// 任务开始前重置 WebView 到空白页
  Future<void> resetPageBeforeStart();

  /// 安排任务完成后的页面延迟卸载
  void schedulePageUnload();

  /// 取消已安排的页面卸载定时器
  void cancelScheduledUnload();

  /// 恢复桌面版 UserAgent
  Future<void> restoreDesktopUserAgent();

  /// 取消其他领域（主页、个人资料）的正在进行任务
  void cancelOtherTasks();

  /// 清理已拦截的非标准 Scheme 记录
  void clearBlockedSchemes();
}
