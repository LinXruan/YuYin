# 余音 YuYin

一个仅面向 Android 的抖音无水印资源下载工具，支持视频、图集和实况图。

> 本项目仅供学习、开发与技术交流使用，禁止任何形式的商业用途。

## 功能

- 解析抖音分享口令、短链和作品长链
- 视频多画质选择，登录后可获取更高画质
- 图集 / 实况图预览、多选并保存到系统相册
- 解析 / 历史 / 设置三个主页面
- 设置 → 调试：查看完整运行日志、长按选中复制、一键复制（附带原始链接 / 嗅探页面 / 当前网页）
- 设置 → 关于：版本、开源地址、制作人与免责声明
- 历史页目前为占位，后续开发

## 使用说明

1. 复制抖音作品的分享链接或口令；
2. 打开余音，粘贴到输入框；
3. 点击“解析作品”；
4. 视频选择画质，图集 / 实况图勾选需要的资源；
5. 保存到系统相册；
6. 如需更高画质，点击右上角“账号登录/提画质”登录抖音。点击登录页的【完成返回】后，按钮会变成“我的主页”。

登录仅用于在解析时获取更高画质，登录状态保存在本机 WebView 中，不会读取或上传账号密码等个人信息。

## 环境与构建

- Flutter 3.47.6 / Dart 3.13.5
- JDK 17
- 仅 Android（minSdk 24 / targetSdk 36）
- 包名：debug `com.debug.yuyin` / release `com.release.yuyin`
- 版本：`1.0.0+113`

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release   # 使用本机独立的 release 私钥签名
```

APK 输出：

- debug：`build/app/outputs/flutter-apk/app-debug.apk`
- release：`build/app/outputs/flutter-apk/app-release.apk`

release 签名读取 `android/key.properties` 与 `android/app/yuyin-release.jks`（均不提交到仓库，需自行备份）。debug / release 包名不同，可同时安装。

## 项目结构

```text
lib/
├── main.dart                  # 应用入口与主题
├── app_info.dart              # 应用名、版本、仓库、作者、登录提示、免责声明
├── pages/
│   ├── app_shell.dart         # 三 Tab 主框架、全局服务与常驻隐藏 WebView
│   ├── parse_page.dart        # 解析页
│   ├── history_page.dart      # 历史占位
│   ├── settings_page.dart     # 设置页
│   ├── debug_page.dart        # 调试日志
│   ├── about_page.dart        # 关于
│   └── login_webview_page.dart
├── services/
│   ├── douyin_sniffer.dart    # 隐藏 WebView 嗅探、任务与兜底
│   ├── douyin_share_api.dart  # iesdouyin 分享页解析
│   ├── js_script_builder.dart # 注入的嗅探脚本
│   └── video_downloader.dart  # 下载并保存到相册
├── models/media_item.dart
├── utils/
│   ├── url_parser.dart
│   ├── log_controller.dart
│   └── login_state_store.dart
└── widgets/                   # 日志、画质、图片选择组件
```

## 技术要点

- 隐藏 WebView 常驻挂载，切换 Tab 或进入设置页时解析不会中断；
- 注入 JS 拦截 fetch / XHR 和页面数据，并配合 iesdouyin 分享页接口和分享页 WebView 兜底；
- 一个 `WebViewController` 同时只挂载一个 `WebViewWidget`；
- 用户取消画质 / 图片选择时调用 `DouyinSniffer.cancelActiveTask()`，停止后台解析和网页加载；
- 不使用第三方状态管理，基于 `ValueNotifier` / `setState` 实现。

## 测试

`flutter test` 覆盖 URL 解析、分享页解析、日志控制器和嗅探纯逻辑，共 43 个单元测试。

## 开源与作者

- 开源地址：<https://github.com/LinXruan/YuYin>
- 制作人：LinXruan

## 免责声明

本项目仅供学习、开发与技术交流使用，禁止任何形式的商业用途。

本应用不提供、不存储任何音视频内容，所有资源均来自抖音公开页面。请勿将本工具用于批量抓取、侵权传播、绕过平台限制或任何违反法律法规及平台协议的行为。

使用者应自行承担因使用本工具产生的一切后果，开发者不承担任何责任。
