# 余音 YuYin

Android 端抖音无水印资源下载工具，支持视频、图集和实况图。

> 仅供学习、开发与技术交流使用，禁止商业用途。

## 功能

- 解析抖音分享口令、短链和作品长链
- 视频多画质选择，登录后可获取更高画质
- 图集 / 实况图预览、多选并保存到系统相册
- 解析 / 历史 / 设置三个主页面，历史页开发中
- 设置内提供调试日志与关于页

## 使用

1. 复制抖音作品的分享链接或口令；
2. 打开余音，粘贴并点击“解析作品”；
3. 视频选择画质，图集 / 实况图勾选需要的资源；
4. 保存到系统相册。

需要更高画质时，点击右上角“抖音登录/提画质”登录抖音。登录仅用于解析，状态只保存在本机 WebView，不会读取或上传账号信息。

## 反馈交流

- QQ 群：`1132880576`（关于页“反馈交流Q群”右侧按钮可一键复制）
- 开源地址：<https://github.com/LinXruan/YuYin>

## 构建

- Flutter 3.47.6 / Dart 3.13.5，JDK 17
- 仅 Android，minSdk 24 / targetSdk 36
- 版本 `1.2.5+135`
- 包名：debug `com.debug.yuyin`，release `com.release.yuyin`（可同时安装）

```bash
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter build apk --release
```

release 签名读取 `android/key.properties` 与 `android/app/yuyin-release.jks`（不提交仓库，请自行备份）。

## 作者

制作人：LinXruan

## 免责声明

本应用不提供、不存储任何音视频内容，资源均来自抖音公开页面。请勿用于批量抓取、侵权传播或违反法律法规及平台协议的行为。使用产生的一切后果由使用者自行承担。
