# PLAN_48：优化更新机制、下载设置与历史记录缩略图离线缓存 (版本 1.4.9+161)

## 一、需求背景与目标

### 1. 需求背景
1. **安装包存储路径外部化**：原安装包存储在应用内部私有目录 `/data/user/0/com.release.yuyin/files/updates/`，在部分定制 ROM 或没有 ROOT 权限的系统安装器访问时可能偶发权限或解析受限，且用户在系统文件管理器中无法直观看到。需要迁移到外部私有存储目录 `/storage/emulated/0/Android/data/com.release.yuyin/files/updates/`。
2. **自动检查更新功能**：用户希望在打开软件 2 秒后自动进行静默检查更新（仅在有更新时弹出更新提醒），默认开启，并在设置中的“下载设置”中增加该开关，同时将板块更名为“下载与更新”。
3. **历史记录交互精简**：去掉历史列表单项的左滑删除效果，防止在浏览历史或误触时误删。
4. **历史记录缩略图离线缓存**：历史记录原本直接使用 `Image.network` 联网加载缩略图，在离线/弱网环境下无法显示，且每次打开历史记录重复网络请求开销极大。需建立本地封面缩略图缓存机制，解析或查看时自动下载落盘缓存，断网时秒级从本地离线加载。
5. **主界面切页稳定性**：保持经典的底层 `IndexedStack` 原生稳态，不再维护左右滑动切页。

---

## 二、详细任务分解

### 任务 1：版本号升级与基础环境同步 (1.4.9+161)
- `pubspec.yaml`: `version: 1.4.9+161`
- `lib/app_info.dart`: `appVersion = '1.4.9+161'`
- `GEMINI.md`: `1.4.9+161`
- `CLAUDE.md`: `1.4.9+161`

### 任务 2：更新包存储目录迁移至外部应用私有存储
- 目标路径：`/storage/emulated/0/Android/data/<package_name>/files/updates/`
- 在 Flutter 中使用 `getExternalStorageDirectory()`，其在 Android 上精确映射到 `/storage/emulated/0/Android/data/<package_name>/files`；
- 拼接 `/updates` 子目录；
- 兜底回退：若外部存储不可用，则安全回退到 `getApplicationSupportDirectory()`。
- Android `file_paths.xml` 中已有 `<external-files-path name="external_files" path="." />`，FileProvider 完全兼容。

### 任务 3：下载设置页面更名与自动检查更新选项
- **持久化配置**：
  - 在 `DownloadSettingsStore` 中增加 `autoCheckUpdate` 字段（`bool` 类型，默认为 `true`），以及 `autoCheckUpdateNotifier`；
  - 保存并读取 `download_settings.json`。
- **UI 调整**：
  - [SettingsPage]：
    - 入口“下载设置”更名为**“下载与更新”**；
    - 副标题更新为“保存位置、画质过滤、自动检查更新”。
  - [DownloadSettingsPage]：
    - 页面标题更名为**“下载与更新”**；
    - 新增 `SwitchListTile`：“自动检查更新”，副标题为“启动 2 秒后自动检测新版本”，默认开启。
- **AppShell 启动延迟 2 秒检测**：
  - 在 `AppShell.initState` 中，延时 2 秒检查 `DownloadSettingsStore.autoCheckUpdate`；
  - 若开启且网络正常，执行静默检查更新 `_checker.checkUpdate()`；
  - 仅在有新版本（`info.hasUpdate == true`）且当前未处于下载中时，在主界面弹出更新弹窗；若已是最新版或报错则完全静默，不干扰用户。

### 任务 4：移除历史记录页面的左滑删除
- 在 `lib/pages/history_page.dart` 中：
  - 移除 `_HistoryCard` 外包裹的 `Dismissible` 组件；
  - 保留并维护多选模式下的底栏批量删除与长按选择逻辑。

### 任务 5：历史记录缩略图本地离线缓存系统
- 创建 `HistoryThumbnailCache` 管理类：
  - 封面缩略图直接保存在应用私有缓存目录 `covers/<md5_hash>.jpg`；
  - 提供 `getThumbnailFile(String url, {String? coverUrl})`；
  - 解析入库时异步下载缓存；
  - 历史页面先读本地缓存，若有则直接 `Image.file`，断网可用；若无且有网则 `Image.network` 并异步落盘。

---

## 三、构建与交付计划
1. 代码编写与全量单元测试覆盖；
2. 执行 `flutter analyze` 确保 0 警告；
3. 执行 `flutter test` 确保 100% 通过；
4. 编译 Release 正式版 APK（`.\tool\build_release_apk.bat all`）；
5. 交付用户测试。
