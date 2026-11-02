import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/auth/auth_contracts.dart';
import 'package:yuyin/services/auth/auth_models.dart';
import 'package:yuyin/services/auth/auth_session_manager.dart';

class MockAuthPersistence implements IAuthPersistence {
  AuthSession? storedSession;
  bool promptDismissed = false;

  @override
  Future<AuthSession?> loadSession() async => storedSession;

  @override
  Future<void> saveSession(AuthSession session) async {
    storedSession = session;
  }

  @override
  Future<void> clearSession() async {
    storedSession = null;
  }

  @override
  Future<bool> isPromptDismissed() async => promptDismissed;

  @override
  Future<void> setPromptDismissed(bool dismissed) async {
    promptDismissed = dismissed;
  }
}

class MockAuthRemoteVerifier implements IAuthRemoteVerifier {
  RemoteVerifyResult nextResult = RemoteVerifyResult.valid(userId: '123456');

  @override
  Future<RemoteVerifyResult> verify(String cookieHeader) async {
    return nextResult;
  }
}

class MockCookieAccessor implements ICookieAccessor {
  String cookieHeader = 'sessionid=abc123456; sid_guard=xyz';
  bool hasSession = true;

  @override
  Future<String> getDouyinCookieHeader() async => cookieHeader;

  @override
  Future<bool> hasSessionCookie() async => hasSession;

  @override
  Future<void> clearDouyinCookies() async {
    cookieHeader = '';
    hasSession = false;
  }
}

void main() {
  group('AuthSessionManager 面向对象会话管理测试', () {
    late MockAuthPersistence persistence;
    late MockAuthRemoteVerifier verifier;
    late MockCookieAccessor cookieAccessor;
    late AuthSessionManager manager;

    setUp(() {
      persistence = MockAuthPersistence();
      verifier = MockAuthRemoteVerifier();
      cookieAccessor = MockCookieAccessor();
      manager = AuthSessionManager(
        persistence: persistence,
        verifier: verifier,
        cookieAccessor: cookieAccessor,
      );
    });

    tearDown(() {
      manager.dispose();
    });

    test('冷启动：本地无会话初始化为 unauthenticated', () async {
      persistence.storedSession = null;
      await manager.initialize();

      expect(manager.status, AuthStatus.unauthenticated);
      expect(manager.isLoggedIn, isFalse);
    });

    test('冷启动：本地有标记但无 Cookie 时自动清除并置为 unauthenticated', () async {
      persistence.storedSession = const AuthSession(
        status: AuthStatus.authenticated,
        userId: '1001',
      );
      cookieAccessor.hasSession = false;

      await manager.initialize();

      expect(manager.status, AuthStatus.unauthenticated);
      expect(manager.isLoggedIn, isFalse);
      expect(persistence.storedSession, isNull);
    });

    test('冷启动：本地有标记且有 Cookie，秒级乐观置为 authenticated 并异步校验', () async {
      persistence.storedSession = const AuthSession(
        status: AuthStatus.authenticated,
        userId: '1001',
      );
      cookieAccessor.hasSession = true;
      verifier.nextResult = RemoteVerifyResult.valid(userId: '1001');

      await manager.initialize();

      expect(manager.status, AuthStatus.authenticated);
      expect(manager.isLoggedIn, isTrue);
    });

    test('权威校验：服务端明确返回 invalid (101/未登录) 自动流转为 expired', () async {
      await manager.markLoggedIn(userId: '1001');
      expect(manager.isLoggedIn, isTrue);

      verifier.nextResult = RemoteVerifyResult.invalid(message: '未登录 (101)');
      final isValid = await manager.verifyRemote();

      expect(isValid, isFalse);
      expect(manager.status, AuthStatus.expired);
      expect(manager.isLoggedIn, isFalse);
      expect(persistence.storedSession, isNull);
    });

    test('权威校验：网络断开/超时容灾，不误登出', () async {
      await manager.markLoggedIn(userId: '1001');
      expect(manager.isLoggedIn, isTrue);

      verifier.nextResult = RemoteVerifyResult.networkError(message: '网络连接超时');
      final isValid = await manager.verifyRemote();

      // 网络异常时保持乐观现状
      expect(isValid, isTrue);
      expect(manager.status, AuthStatus.authenticated);
      expect(manager.isLoggedIn, isTrue);
    });

    test('嗅探器通知会话失效：自动清理持久化并置为 expired', () async {
      await manager.markLoggedIn(userId: '1001');
      expect(manager.isLoggedIn, isTrue);

      await manager.notifySessionExpired(reason: '主页面遭遇登录拦截');

      expect(manager.status, AuthStatus.expired);
      expect(manager.isLoggedIn, isFalse);
      expect(persistence.storedSession, isNull);
    });

    test('主动退出登录：清理持久化与 Cookie 并置为 unauthenticated', () async {
      await manager.markLoggedIn(userId: '1001');
      expect(manager.isLoggedIn, isTrue);

      await manager.logout();

      expect(manager.status, AuthStatus.unauthenticated);
      expect(manager.isLoggedIn, isFalse);
      expect(persistence.storedSession, isNull);
      expect(cookieAccessor.hasSession, isFalse);
    });
  });
}

