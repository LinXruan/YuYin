import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../utils/login_state_store.dart';
import 'auth_contracts.dart';
import 'auth_models.dart';
import 'douyin_passport_verifier.dart';
import 'webview_cookie_accessor.dart';

/// 面向对象的全局会话状态生命周期管理器
///
/// 遵循单源真理（Single Source of Truth）原则与依赖倒置（DIP）。
/// 继承 [ChangeNotifier]，任何状态流转均可实时响应至 UI 与嗅探器。
class AuthSessionManager extends ChangeNotifier {
  AuthSessionManager({
    IAuthPersistence? persistence,
    IAuthRemoteVerifier? verifier,
    ICookieAccessor? cookieAccessor,
  })  : _persistence = persistence ?? LoginStateStore.instance,
        _verifier = verifier ?? DouyinPassportVerifier(),
        _cookieAccessor = cookieAccessor ?? WebViewCookieAccessor();

  final IAuthPersistence _persistence;
  final IAuthRemoteVerifier _verifier;
  final ICookieAccessor _cookieAccessor;

  AuthSession _session = AuthSession.unauthenticated;
  bool _isVerifying = false;
  Future<bool>? _pendingVerifyFuture;

  /// 当前会话快照
  AuthSession get session => _session;

  /// 当前认证状态
  AuthStatus get status => _session.status;

  /// 是否具备可用登录状态
  bool get isLoggedIn => _session.isValid;

  /// 当前用户 ID（若有）
  String? get userId => _session.userId;

  /// 初始化会话（冷启动时调用）
  ///
  /// 采用“本地乐观秒开 + 异步服务端权威校验”策略，避免白屏与卡顿。
  Future<void> initialize() async {
    try {
      final saved = await _persistence.loadSession();
      if (saved == null || saved.status != AuthStatus.authenticated) {
        _setSession(AuthSession.unauthenticated);
        return;
      }

      // 二次比对本地 Cookie 库是否存在基础字段
      final hasCookie = await _cookieAccessor.hasSessionCookie();
      if (!hasCookie) {
        // 本地 Cookie 已不存在，立即清理持久化
        await _persistence.clearSession();
        _setSession(AuthSession.unauthenticated);
        return;
      }

      // 本地有标记且有 Cookie：先乐观呈现已登录状态，供 UI 极速渲染
      _setSession(saved);

      // 后台静默发起服务端权威校验，核实凭据在服务端是否存活
      unawaited(verifyRemote());
    } catch (_) {
      _setSession(AuthSession.unauthenticated);
    }
  }

  /// 向抖音官方服务端发起权威核验
  ///
  /// 返回当前会话在服务端的真实有效性。若服务端明确返回已失效（101/未登录），
  /// 自动流转为 [AuthStatus.expired] 并清除本地标记；若离线则容灾保护。
  Future<bool> verifyRemote({bool force = false}) {
    if (_isVerifying && _pendingVerifyFuture != null) {
      return _pendingVerifyFuture!;
    }

    _pendingVerifyFuture = _doVerifyRemote();
    return _pendingVerifyFuture!;
  }

  Future<bool> _doVerifyRemote() async {
    _isVerifying = true;
    try {
      final cookieHeader = await _cookieAccessor.getDouyinCookieHeader();
      if (cookieHeader.isEmpty) {
        await _handleExpired('本地缺少 Cookie 凭据');
        return false;
      }

      final result = await _verifier.verify(cookieHeader);
      switch (result.status) {
        case RemoteVerifyStatus.valid:
          final newSession = _session.copyWith(
            status: AuthStatus.authenticated,
            userId: result.userId ?? _session.userId,
            lastVerifiedAt: DateTime.now(),
          );
          await _persistence.saveSession(newSession);
          _setSession(newSession);
          return true;

        case RemoteVerifyStatus.invalid:
          // 服务端明确拒绝（如被踢、会话过期）
          await _handleExpired(result.message ?? '服务端会话已失效');
          return false;

        case RemoteVerifyStatus.networkError:
          // 网络容灾：离线或超时不作失效处理，保留现有可用性
          return _session.isValid;
      }
    } catch (_) {
      return _session.isValid;
    } finally {
      _isVerifying = false;
      _pendingVerifyFuture = null;
    }
  }

  /// 标记登录成功（登录页回调）
  Future<void> markLoggedIn({String? userId}) async {
    final newSession = AuthSession(
      status: AuthStatus.authenticated,
      userId: userId,
      lastVerifiedAt: DateTime.now(),
    );
    await _persistence.saveSession(newSession);
    _setSession(newSession);
  }

  /// 嗅探器或主 WebView 观察到服务端登录拦截时主动调用
  Future<void> notifySessionExpired({String? reason}) async {
    await _handleExpired(reason ?? '检测到服务端会话失效');
  }

  /// 主动退出登录
  Future<void> logout() async {
    await _persistence.clearSession();
    await _cookieAccessor.clearDouyinCookies();
    _setSession(AuthSession.unauthenticated);
  }

  Future<void> _handleExpired(String reason) async {
    await _persistence.clearSession();
    _setSession(const AuthSession(status: AuthStatus.expired));
  }

  void _setSession(AuthSession newSession) {
    if (_session == newSession) return;
    _session = newSession;
    notifyListeners();
  }
}

