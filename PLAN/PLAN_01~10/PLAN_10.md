# PLAN_10：底部文字样式、日志前缀与图标/启动页修复（112）

## 背景

PLAN_9 已安装到真机，反馈三个问题：

1. 解析页底部“本地、解析、隐私”文字太小，需要放大并改为灰色；
2. 日志中的 `[捕获]` 前缀全部改为 `[解析]`；
3. App 图标和启动页的音符异常大，但 APK 内 `res/mipmap` 的 PNG 图标音符大小正常。

版本更新为 **112**（`1.0.0+112`）。

## 问题 3 分析与修复方案

当前启动图标走的是 Android 8+ 自适应图标（`mipmap-anydpi-v26/ic_launcher.xml`），其前景是 **vector drawable** `ic_launcher_foreground.xml`；启动页也使用 **vector drawable** `launch_logo.xml`。真机上这两处 vector 渲染出的音符明显偏大，而 `mipmap-*/ic_launcher.png` 中的图片（用 MaterialIcons 字体渲染）大小正常。

修复思路：不再使用 vector 作为图标前景和启动 logo，全部改用已经验证正常的 PNG 资源：

- 用 `tool/generate_app_icon.py` 生成：
  - `mipmap-<density>/ic_launcher_foreground.png`：108dp 透明画布 + 居中深色音符（自适应图标前景）；
  - `drawable-<density>/launch_logo.png`：120dp 浅粉圆底 + 深色音符（启动页）；
- 自适应图标 XML 的前景改为 `@mipmap/ic_launcher_foreground`；
- `launch_background.xml` / `drawable-v21` 改为 `<bitmap android:src="@drawable/launch_logo" android:gravity="center"/>`；
- `values-v31` / `values-night-v31` 的 `windowSplashScreenAnimatedIcon` 继续引用 `@drawable/launch_logo`（此时是 PNG）；
- 删除 `drawable/ic_launcher_foreground.xml`、`drawable/launch_logo.xml` 两个 vector；
- 保留原有 `mipmap-*/ic_launcher.png` 与 `ic_launcher_round.png`。

密度尺寸：

| 密度 | 前景 108dp | 启动 logo 120dp |
| --- | --- | --- |
| mdpi | 108px | 120px |
| hdpi | 162px | 180px |
| xhdpi | 216px | 240px |
| xxhdpi | 324px | 360px |
| xxxhdpi | 432px | 480px |

## 其他修改

### 1. 底部文字

`lib/pages/parse_page.dart` 底部静态文字：

- 字号从 `bodySmall`（约 12）调整为 **16**；
- 颜色改为灰色 `Colors.grey.shade600`；
- 仍然只是纯文字，不可点击。

### 2. 日志前缀

`lib/pages/app_shell.dart` 的 `onLog` 前缀：

- `[捕获]` → `[解析]`（包含代码注释同步修改）。

## 版本

- `pubspec.yaml`：`version: 1.0.0+112`
- `lib/app_info.dart`：`appVersion = '1.0.0+112'`

## 涉及文件

**修改**
- `pubspec.yaml`
- `lib/app_info.dart`
- `lib/pages/parse_page.dart`
- `lib/pages/app_shell.dart`
- `tool/generate_app_icon.py`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml`
- `android/app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml`
- `android/app/src/main/res/drawable/launch_background.xml`
- `android/app/src/main/res/drawable-v21/launch_background.xml`

**新增**
- `android/app/src/main/res/mipmap-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/ic_launcher_foreground.png`
- `android/app/src/main/res/drawable-{mdpi,hdpi,xhdpi,xxhdpi,xxxhdpi}/launch_logo.png`

**删除**
- `android/app/src/main/res/drawable/ic_launcher_foreground.xml`
- `android/app/src/main/res/drawable/launch_logo.xml`

## 验证结果

- `flutter analyze`：No issues found
- `flutter test`：35 个测试全部通过
- `flutter build apk --debug`：构建成功
- APK：`build/app/outputs/flutter-apk/app-debug.apk`
- aapt 校验：
  - versionCode=`112`
  - versionName=`1.0.0`
  - application-label=`余音`
  - 自适应图标仍使用 `mipmap-anydpi-v26/ic_launcher.xml`
  - APK 内包含 `res/mipmap-*/ic_launcher_foreground.png` 与 `res/drawable-*/launch_logo.png`
  - vector `ic_launcher_foreground.xml` / `launch_logo.xml` 已完全移除
- PNG 尺寸：前景 108/162/216/324/432，启动 logo 120/180/240/360/480
- 当前 adb 设备已断开，APK 已交付；真机安装后由用户确认桌面图标、启动页、底部文字和 `[解析]` 日志前缀。
