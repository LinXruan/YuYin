# PLAN_12：无调用代码清理与核心捕获链路加固（113）

## 背景

接手评估发现两类问题最值得先处理：

1. `lib/` 内存在无调用代码和模板残留，容易误导新维护者；
2. 核心捕获链路 `DouyinSniffer` 的调试日志在解析成功后“截断”，且错误收尾状态不干净。

本次范围：**只做删除无调用代码 + 核心链路加固**，不重构 Dart/JS 重复解析规则，不收紧网络安全配置；版本升到 **`1.0.0+113`**。

## 关键诊断：调试日志为什么被截断

- `_onJavaScriptMessage` 开头用 `_acceptMessages` 挡住了**所有** JS 消息，包括 `type=log`；
- `_finishWithItems` 收到结果后立即设置 `_acceptMessages = false`，而 JS 在 `postMessage(result)` 之后才发送“解析完成: 共 N 个资源”，因此这条及后续日志被丢弃；
- PLAN_9 增加的 `_isTaskActive` 导航守卫和 `cancelActiveTask` 是正确的，不应回退；问题在于“结果只接收一次”和“日志是否接收”共用一个开关。

## 目标

1. 删除确认无调用方的代码与模板残留；
2. 拆分日志/结果接收开关，让调试日志包含 JS 收尾信息；
3. 统一日志出口，让复制出的调试日志包含失败原因；
4. 收干净任务结束状态，补齐时间常量与 A/B/C 兜底图例；
5. 为可抽离的纯逻辑补单元测试；
6. 版本升到 `1.0.0+113`，现有 35 个测试保持通过。

## 方案

### 1. 删除无调用代码与模板残留

| 文件 | 改动 |
| --- | --- |
| `lib/services/video_downloader.dart` | 删除 `downloadToGallery`、`downloadMediaList`（无调用方，注释引用了不存在的“旧版首页”） |
| `lib/models/media_item.dart` | 删除无调用的 `typeLabel` |
| `lib/services/douyin_sniffer.dart` | 删除 `export '../models/media_item.dart';` |
| `lib/pages/parse_page.dart`、`lib/services/video_downloader.dart` | 补显式 `import '../models/media_item.dart';` |
| `pubspec.yaml` | 描述改为项目描述；删除未使用的 `cupertino_icons` |
| `android/app/build.gradle.kts` | 删除过期的模板 TODO |

### 2. 核心链路加固

#### 2.1 拆分 `_acceptMessages` 与 `_acceptLogs`

新增 `_acceptLogs` 字段，生命周期：

| 时机 | `_acceptMessages` | `_acceptLogs` |
| --- | --- | --- |
| 新任务开始 | false | false |
| `onPageStarted` 且 URL 合法、任务活跃 | true | true |
| 收到 result（`_finishWithItems` 开头） | false | 保持 true，等待 Cookie 读取 |
| Cookie 读取完成且 identity 校验通过 | false | false（先关日志，再输出 Dart summary） |
| `_finishWithError` / `cancelActiveTask` / `dispose` | false | false |

`_onJavaScriptMessage` 中 `type == 'log'` 只检查 `_acceptLogs`；`hint` / `result` 检查 `_acceptMessages` 并补充 `_isTaskActive` 守卫。

把 `js_script_builder.dart` 中 `log('解析完成: ...')` 移到 `postMessage(result)` 之前，保证该日志在 result 之前稳定到达。

#### 2.2 统一日志出口 `_log`

新增 `_log(String message)`：同时 `debugPrint('[JS-Sniffer] $message')` 和 `onLog?.call(message)`。替换所有 `onLog?.call` 与诊断型 `debugPrint`，合并四对重复输出；`_injectScript` 失败和验证码检测失败每任务只记首次；取消后的 UA 恢复失败与 `about:blank` 加载失败保留 `debugPrint`。

#### 2.3 任务状态收尾

- `_finishWithError`：先校验 taskId，再关闭两个开关，取出并清空 `_completer`，停定时器，最后 `completeError`；
- `_finishWithItems`：Cookie `await` 后 identity 校验不通过直接 return，不清 `_completer`、不改 `_acceptLogs`；通过后关 `_acceptLogs`、输出 summary、完成 completer、在 identity 前提下清空；
- `cancelActiveTask`：两个开关置 false，先清空 `_completer` 再 `completeError`，保留 `about:blank`；
- `dispose`：两个开关置 false，复用 `_finishWithError`。

#### 2.4 时间常量、A/B/C 图例与纯逻辑测试

- 类顶部补 A/B/C 图例；
- 新增 `_kTaskTimeout`(30s)、`_kInjectInterval`(1.2s)、`_kNoteFallbackDelay`(3s)、`_kVideoFallbackDelay`(8s)、`_kLateFallbackAt`(18s)、`_kWebViewFallbackTimeout`(12s)、`_kFallbackSafetyMargin`(2s)、`_kFallbackMinTimeout`(5s)、`_kFallbackMinRemaining`(6s)，替换内联数字；
- 抽取 `parseChannelItems`、`webViewFallbackTimeoutFor`、`shareFallbackErrorMessage` 三个 `@visibleForTesting` 静态方法；
- 新增 `test/douyin_sniffer_logic_test.dart`；
- `js_script_builder.dart` 的 12000ms 仅加注释，不合并常量。

### 3. 版本号与文档

- `pubspec.yaml`、`lib/app_info.dart`、`README.md`、`CLAUDE.md`：版本 `1.0.0+113`；
- `README.md` 测试数量按实际结果更新；
- `CLAUDE.md` 第 4 节补充日志/结果开关分离约束。

## 涉及文件

**新增**
- `PLAN/PLAN_12.md`
- `test/douyin_sniffer_logic_test.dart`

**修改**
- `lib/services/douyin_sniffer.dart`
- `lib/services/js_script_builder.dart`
- `lib/services/video_downloader.dart`
- `lib/models/media_item.dart`
- `lib/pages/parse_page.dart`
- `pubspec.yaml` / `pubspec.lock`
- `lib/app_info.dart`
- `README.md`
- `CLAUDE.md`
- `android/app/build.gradle.kts`

## 验证

- `flutter analyze`：`No issues found`
- `flutter test`：现有 35 个 + 新增纯逻辑用例全部通过
- `flutter build apk --debug`：构建成功
- 真机回归：视频/图文解析成功日志完整、取消后日志立即停止、超时后重新解析正常、连续两次解析无旧任务日志、复制日志包含诊断信息、下载保存正常

## 验证结果

- `flutter pub get`：成功；移除 `cupertino_icons` 后依赖解析正常
- `flutter analyze`：No issues found
- `flutter test`：43 个测试全部通过（原有 35 + 新增 8）
- `flutter build apk --debug`：构建成功（Gradle assembleDebug 约 51 秒）
- APK：`build/app/outputs/flutter-apk/app-debug.apk`（约 148MB）
- aapt 校验：package=`com.debug.yuyin`，versionCode=`113`，versionName=`1.0.0`，application-label=`余音`
- 真机回归：待用户完成（视频/图文成功日志、取消后日志停止、超时后重试、连续两次解析、复制日志、下载保存）