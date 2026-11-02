# PLAN_45：基于面向对象架构的会话全生命周期管理与画质弹性决议机制 (版本 1.4.2+155)

## 一、需求背景与目标

针对当前系统中存在的两大致命问题：
1. **登录状态纯本地推导引发“伪在线”盲区**：服务端单方面踢出/会话过期无法感知；
2. **嗅探器画质等待黑洞引发“30 秒假死”**：当处于登录态（或误判登录态）时，嗅探器拿到分享页视频后将结果扣住，等待主 WebView 的唯一出口是 30 秒硬超时（`_kTaskTimeout`），导致用户长时间转圈卡顿。

本版本（1.4.2+155）通过**面向对象设计（OOP）**进行架构重构与痛点根治：
- 抽取 **`AuthSessionManager`** 统一掌管会话生命周期与单源真理，依赖倒置解耦持久化与服务端鉴权；
- 抽取 **`QualityResolutionPolicy`** 独立掌管画质竞争决策，引入 4 秒有界等待窗口与登录墙快速降级，彻底消灭 30 秒硬卡死；
- 保持纯原生 Flutter/Dart 架构，不引入任何第三方状态管理库。

---

## 二、系统架构与技术设计

```mermaid
classDiagram
    direction TB

    class AuthStatus {
        <<enumeration>>
        unauthenticated
        authenticated
        verifying
        expired
    }

    class AuthSession {
        +AuthStatus status
        +String? userId
        +DateTime? lastVerifiedAt
        +bool get isValid
    }

    class IAuthPersistence {
        <<interface>>
        +loadSession() Future~AuthSession?~
        +saveSession(session) Future~void~
        +clearSession() Future~void~
        +isPromptDismissed() Future~bool~
        +setPromptDismissed(value) Future~void~
    }

    class IAuthRemoteVerifier {
        <<interface>>
        +verify(cookieHeader) Future~RemoteVerifyResult~
    }

    class ICookieAccessor {
        <<interface>>
        +getDouyinCookieHeader() Future~String~
        +hasSessionCookie() Future~bool~
        +clearDouyinCookies() Future~void~
    }

    class AuthSessionManager {
        -AuthSession _currentSession
        +AuthSession get session
        +AuthStatus get status
        +bool get isLoggedIn
        +initialize() Future~void~
        +verifyRemote({force}) Future~bool~
        +markLoggedIn(userId) Future~void~
        +notifySessionExpired() Future~void~
        +logout() Future~void~
    }

    class QualityResolutionPolicy {
        +Duration qualityWaitWindow
        +onShareVideoArrived(result, isAuthed) ResolutionAction
        +onWebVideoArrived(result) ResolutionAction
        +onWaitTimeout() ResolutionAction
        +onLoginWallDetected() ResolutionAction
    }

    class DouyinSniffer {
        -QualityResolutionPolicy _qualityPolicy
        -AuthSessionManager _authManager
        +cancelActiveTask()
        +sniffUrl(url)
    }

    AuthSessionManager --> AuthSession : 维护
    AuthSessionManager --> AuthStatus : 使用
    AuthSessionManager ..> IAuthPersistence : 依赖抽象
    AuthSessionManager ..> IAuthRemoteVerifier : 依赖抽象
    AuthSessionManager ..> ICookieAccessor : 依赖抽象
    DouyinSniffer --> QualityResolutionPolicy : 决议画质
    DouyinSniffer ..> AuthSessionManager : 监听/感知失效
```

---

## 三、文件修改清单

| 序号 | 文件路径 | 修改类型 | 说明 |
| :--- | :--- | :--- | :--- |
| 1 | `pubspec.yaml` | MODIFY | 版本提升至 `1.4.2+155` |
| 2 | `lib/app_info.dart` | MODIFY | 常量更新为 `1.4.2+155` |
| 3 | `GEMINI.md` / `CLAUDE.md` | MODIFY | 维护守则同步至 `1.4.2+155` |
| 4 | `lib/services/auth/auth_models.dart` | NEW | 定义 `AuthStatus`、`AuthSession`、`RemoteVerifyResult` 等数据模型 |
| 5 | `lib/services/auth/auth_contracts.dart` | NEW | 定义 `IAuthPersistence`、`IAuthRemoteVerifier`、`ICookieAccessor` 抽象接口 |
| 6 | `lib/services/auth/douyin_passport_verifier.dart` | NEW | 基于 Dio 实现官方 `/passport/web/account/info/` 鉴权核验 |
| 7 | `lib/services/auth/auth_session_manager.dart` | NEW | 面向对象的会话生命周期管理器（继承 `ChangeNotifier`） |
| 8 | `lib/services/sniffer/quality_resolution_policy.dart` | NEW | 画质竞争与降级决策策略对象（消灭 30 秒卡死） |
| 9 | `lib/services/douyin_sniffer.dart` | MODIFY | 接入 `QualityResolutionPolicy` 与会话失效感知，移除硬编码 30 秒挂起 |
| 10 | `lib/utils/login_state_store.dart` | MODIFY | 重构成作为 `IAuthPersistence` 的实现，保持向后兼容并支持适配器注入 |
| 11 | `lib/pages/app_shell.dart` | MODIFY | 接入 `AuthSessionManager`，统一驱动全局 UI 与登录态校验 |
| 12 | `lib/pages/parse_page.dart` | MODIFY | 登录提示条直接监听 `AuthSessionManager` |
| 13 | `lib/pages/login_webview_page.dart` | MODIFY | 登录成功/登出事件对接 `AuthSessionManager` |
| 14 | `test/auth_session_manager_test.dart` | NEW | 针对 Mock Verifier/Persistence 的纯内存 100% 鉴权单测 |
| 15 | `test/quality_resolution_policy_test.dart` | NEW | 针对画质竞争、超时降级与登录墙拦截的独立策略单测 |
| 16 | `PLAN/PLAN_41~50/PLAN_45.md` | MODIFY | 归档完整计划与设计 |

---

## 四、验证计划

1. **自动化测试**：
   - 运行 `flutter analyze` 确保 0 issues；
   - 运行 `flutter test`，确保原有 183 项测试及新增的会话与策略单元测试全部全绿通过。
2. **边界与逻辑验证**：
   - 模拟未登录状态：通道 B 秒级完成；
   - 模拟已登录有效：通道 A 4 秒内晋升超清多码率；
   - 模拟伪在线（已失效）：4 秒有界窗口超时或登录墙拦截后立即降级采纳通道 B，不再挂死 30 秒，且联动重置登录状态。
