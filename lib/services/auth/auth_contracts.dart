import 'auth_models.dart';

/// 本地会话持久化抽象契约
abstract class IAuthPersistence {
  /// 读取本地持久化的会话（包含标记与已保存的公开用户 ID）
  Future<AuthSession?> loadSession();

  /// 保存当前会话
  Future<void> saveSession(AuthSession session);

  /// 清除持久化的会话数据
  Future<void> clearSession();

  /// 用户是否已选择“不再显示”登录提示
  Future<bool> isPromptDismissed();

  /// 设置“不再显示”登录提示状态
  Future<void> setPromptDismissed(bool dismissed);
}

/// 远端权威鉴权核验抽象契约
abstract class IAuthRemoteVerifier {
  /// 携带当前 Cookie 字符串，向服务端发起轻量鉴权探测
  Future<RemoteVerifyResult> verify(String cookieHeader);
}

/// 底层 Cookie 访问器契约（解耦 WebViewCookieManager）
abstract class ICookieAccessor {
  /// 获取抖音域名下的完整 Cookie 请求头字符串 (如 "sessionid=xxx; sid_guard=yyy")
  Future<String> getDouyinCookieHeader();

  /// 检查当前 Cookie 库中是否包含核心登录凭据字段
  Future<bool> hasSessionCookie();

  /// 清理抖音域名相关的 WebView 会话 Cookie
  Future<void> clearDouyinCookies();
}

