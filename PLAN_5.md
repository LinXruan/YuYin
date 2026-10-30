# 阶段五：修复画质选项，修改 APK 基础参数（Step 25 ~ Step 27）

> 抖音无水印下载器 (Flutter Android) 原子化开发计划 by gemini4 · 第 5/5 部分

## Step 25：修复视频“未知画质”抢跑 Bug
**目标**：更新开发守则，并防止 JS 轮询在完整 `bit_rate` 列表加载完成前被兜底逻辑提前截胡。

1. 修改 `lib/services/js_script_builder.dart`：
   - **记录首次注入时间戳**：在 `window` 上记录当前网页嗅探的起始时间 `if (!window.__dyStartTime) window.__dyStartTime = Date.now();`（注意：如果检测到 `location.href` 发生变化，重置 `__dyStartTime = Date.now()`）。
   - **同时兼容两种画质列表结构**：在提取视频多档位时，除了读取 JSON 树中的 `video.bit_rate` 数组外，额外兼容读取 `window.player?.config?.awemeInfo?.video?.bitRateList`（如有），确保拿到完整的清晰度、码率（`bit_rate` / `bitRate`）和大小（`data_size` / `dataSize`）。
   - **核心修复——推迟兜底逻辑（防抢跑）**：
     - 当判定为普通视频（非图文）时，将提取结果分为两类：**“完整画质结果”**（成功从 `bit_rate` / `bitRateList` 提取到带分辨率和码率的档位）和 **“降级兜底结果”**（仅从单一 `play_addr` 或 DOM `<video>` 标签抓到的无码率、未知画质地址）。
     - 如果拿到的是**“完整画质结果”**，立即调用 `DouyinChannel.postMessage` 返回。
     - 如果只拿到**“降级兜底结果”**，检查 `Date.now() - window.__dyStartTime` 是否小于 `8000`（8 秒）：
       - **若小于 8 秒**：说明完整数据包或 XHR 接口可能还在加载中，**暂不发送结果**，打印一条日志 `[JS-Sniffer] 已发现基础视频流，正在等待完整画质列表(bit_rate)...`，等待后续轮询。
       - **若已超过 8 秒**：说明该视频确实没有多档位数据，此时才允许将“降级兜底结果”发送给 Flutter。
2. 运行 `flutter analyze` 确保无语法错误。
3. **完成后立即停下并汇报，等待指令进入 Step 25。**

---

## Step 26：修改应用名称为“余音”、版本为 1.0.0+106、包名为 `com.down.yuyin`
**目标**：完成 App 品牌信息、版本号与 Android 包名（Application ID & Namespace）的全面替换。

1. 修改 `pubspec.yaml`：
   - 将 `version:` 字段修改为 `version: 1.0.0+106`（对应版本名称 `1.0.0`，版本号/构建号 `106`）。
2. 修改 `android/app/build.gradle`（或 `build.gradle.kts`）：
   - 将 `namespace` 修改为 `"com.down.yuyin"`。
   - 将 `defaultConfig` 下的 `applicationId` 修改为 `"com.down.yuyin"`。
3. 修改 `android/app/src/main/AndroidManifest.xml`：
   - 将 `<application>` 标签中的 `android:label` 修改为 `"余音"`。
   - 检查 `AndroidManifest.xml`（含 `main`、`debug`、`profile` 目录）中是否写死了旧的 `package="..."` 属性，如有则移除或同步改为 `com.down.yuyin`。
4. 迁移 Android 原生入口类目录（关键，防止安装后启动闪退）：
   - 找到 `android/app/src/main/kotlin/`（或 `java/`）下的 `MainActivity.kt`。
   - 将其移动到 `android/app/src/main/kotlin/com/down/yuyin/MainActivity.kt`，并将文件首行的 `package` 声明修改为 `package com.down.yuyin`，同时删除旧的空包名文件夹。
5. 修改 `lib/pages/home_page.dart`（及 `lib/main.dart`）：
   - 将 `MaterialApp` 的 `title` 和首页 `AppBar` 的标题文案同步更新为 `余音`（或 `余音 - 抖音无水印下载`）。
6. 运行 `flutter pub get` 和 `flutter analyze` 确保零错误。
7. **完成后立即停下并汇报，等待指令进入 Step 26。**

---

## Step 27：清理构建缓存并打包测试“余音” APK
**目标**：由于更改了 Android 包名与原生目录结构，执行干净构建并验证新包。

1. 检查确认当前没有运行电脑端安卓模拟器（保护 16GB 内存）。
2. 由于修改了包名 `com.down.yuyin`，先运行 `flutter clean` 和 `flutter pub get` 清理旧包名的构建缓存。
3. 运行 `flutter build apk --debug` 构建全新的 APK。
4. 若当前已通过 USB 连接真机，运行 `adb install -r build\app\outputs\flutter-apk\app-debug.apk` 安装到手机。
5. **完成后向用户汇报生成的 APK 路径与版本信息。**

