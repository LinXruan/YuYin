# PLAN_49：永久自适应屏幕刷新率与高刷跟随 (版本 1.5.0+162)

## 一、需求背景与目标

### 1. 需求背景
1. **屏幕刷新率锁 60Hz 痛点**：部分 Android 设备（尤其小米 HyperOS/MIUI、OPPO ColorOS 等厂商系统）由于策略管控，默认将未声明特定类别或未请求高刷窗口的 Flutter 应用锁死在 60Hz。用户在高刷屏（90Hz / 120Hz / 144Hz）上滑动、切页和交互时，感觉明显不如系统自带应用跟手流利。
2. **极简免配置设计**：不需要在设置页面中增加任何复杂开关，直接在应用底层**永久开启屏幕刷新率跟随**。设备支持多高就自适应跑到多高（60Hz/90Hz/120Hz/144Hz 等），不给用户增加心智负担。
3. **刷新率检测与透明日志**：应用启动时自动检测底层物理屏幕所支持的所有刷新率档位以及当前激活刷新率，并在调试日志中输出一条说明（例如 `[系统] 屏幕已启用自适应高刷跟随: 当前 120 Hz (设备最高支持 120 Hz)`），方便用户与开发者直观核验。

---

## 二、详细任务分解

### 任务 1：版本号升级与基础环境同步 (1.5.0+162)
- `pubspec.yaml`: `version: 1.5.0+162`
- `lib/app_info.dart`: `appVersion = '1.5.0+162'`
- `GEMINI.md`: `1.5.0+162`
- `CLAUDE.md`: `1.5.0+162`
- `PLAN/PLAN_41~50/PLAN_49.md`: 归档方案

### 任务 2：Android 原生层永久自适应高刷
- 在 `android/app/src/main/kotlin/com/debug/yuyin/MainActivity.kt` 中：
  - 实现 `enableAdaptiveHighRefreshRate()`：
    - 读取 `Display.supportedModes`；
    - 匹配当前分辨率下刷新率最高的 `Display.Mode`；
    - 设定 `window.attributes.preferredDisplayModeId = bestMode.modeId`；
    - Android 11+（API 30+）同步设置 `preferredMaxDisplayRefreshRate = bestMode.refreshRate`；
    - 在 `onCreate` 以及 `onWindowFocusChanged` 中自动调用，确保窗口常驻处于自适应最高硬件高刷模式；
  - 注册 MethodChannel: `com.debug.yuyin/display_mode`，提供 `getDisplayInfo` 方法返回当前与最高刷新率；
- 在 `android/app/src/main/AndroidManifest.xml` 中：
  - `<application>` 增加 `android:appCategory="video"`，防系统省电机制锁帧。

### 任务 3：Flutter Dart 层检测与调试汇报
- 创建 `lib/utils/display_mode_service.dart`：
  - `init({LogController? logs})`：异步向原生通道查询当前生效刷新率与最高刷新率；
  - 输出格式化日志：`[系统] 屏幕已启用自适应高刷跟随: 当前 xx Hz (设备最高支持 xx Hz)`；
- 在 `lib/pages/app_shell.dart` 的 `initState` 中调用初始化；
- 在 `lib/services/agent_automation_server.dart` 中增加 `/api/display` 接口，并在 `/api/status` 中输出 `display` 字段；
- 在 `tool/agent_cmd.bat` 与 `tool/agent_bridge.ps1` 中支持 `display` 指令。

### 任务 4：质量验证
- 编写 `test/display_mode_service_test.dart` 与 `test/plan_49_test.dart`；
- 执行 `flutter analyze` 确保 0 警告；
- 执行 `flutter test` 确保 100% 全部通过。
