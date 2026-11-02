# PLAN_39：项目空间减负、冗余清理与构建自动清理长效机制

## 一、需求背景与目标

1. **项目体积异常膨胀**：
   - 当前项目根目录总体积高达 **10.08 GB**，严重消耗本地磁盘空间；
   - 经全面递归扫描定位，**99.8%** 的体积由本地构建中间缓存与历史未清理安装包引起；
2. **远程推送差异解释**：
   - 阐明为何本地 10GB 文件夹在推送到 GitHub 时只推送了十几 MB，解释 `.gitignore` 的核心机制与保护签名私钥等安全机密的作用；
3. **消除现有冗余（立即瘦身）**：
   - 清除堆积在 `build\app\outputs\flutter-apk\` 下的各历史版本 APK（释放约 2.0 GB）；
   - 清理 `build\test_cache\` 单元测试快照缓存（释放约 1.85 GB）；
   - 清理 `.dart_tool\flutter_build\` 编译哈希快照缓存（释放约 3.72 GB）；
   - 清理 `log\` 临时日志；
4. **建立长效自动清理机制（防止再次膨胀）**：
   - 升级 `tool/build_debug_apk.bat`：构建时自动清理旧版本 debug 安装包与测试缓存，仅保留当前版本；
   - 升级 `tool/build_release_apk.bat`：发版构建后自动清理旧版本 release 安装包，输出目录始终干净；
   - 新增 `tool/clean_project.bat`：提供一键极速日常瘦身（`quick`）与全量深度重置（`full`）能力。

---

## 二、项目空间体检数据与根因定位

### 1. 各级目录占用明细

| 目录/文件 | 占用体积 | 占比 | 包含的核心内容 | 性质与处理策略 |
| :--- | :--- | :--- | :--- | :--- |
| **`build/`** | **6,231.12 MB (~6.23 GB)** | **61.9%** | Gradle 中间产物、历史 APK、测试快照 | **纯本地构建缓存与历史产物（可安全清理）** |
| ├─ `build\app\intermediates\` | 2,274.48 MB (~2.27 GB) | 22.6% | Gradle 编译 dex、mergeAssets 中间缓存 | Gradle 本地构建缓存 |
| ├─ `build\app\outputs\` | 2,026.38 MB (~2.02 GB) | 20.1% | **1.2.6~1.3.5 全版本历史 APK 安装包堆积** | **冗余文件（只保留最新 v1.3.5）** |
| ├─ `build\test_cache\build\` | 1,848.18 MB (~1.85 GB) | 18.4% | **39 个 `*.cache.dill.track.dill` 测试快照** | **冗余缓存（立即删除）** |
| └─ 其他中间产物 | ~82 MB | 0.8% | gal, webview, native_assets 中间件 | 构建中间件 |
| **`.dart_tool/`** | **3,812.26 MB (~3.81 GB)** | **37.9%** | **近 70 个哈希构建快照 (`flutter_build/`)** | **冗余缓存（立即删除）** |
| **`android/`** | 14.53 MB | 0.1% | 原生 Gradle 配置与构建脚本 | 核心配置 |
| **`.git/`** | 12.05 MB | 0.1% | Git 版本历史库 | 必须保留 |
| **`sources/`** | 10.71 MB | 0.1% | 测试视频素材(8.1MB)、音频(2.6MB)、油猴脚本 | 测试素材（保持保留） |
| **`lib/`** | 0.27 MB | <0.01% | 纯 Dart 核心业务源码（34 个文件） | 核心资产 |
| **`PLAN/`** | 0.27 MB | <0.01% | 规划与设计文档（PLAN_01 ~ 39） | 核心资产 |
| **`test/`** | 0.09 MB | <0.01% | 18 个测试套件（140 个测试用例） | 核心资产 |
| **其他文件** | <0.5 MB | <0.01% | 脚本、README 等 | 核心资产 |
| **总计** | **约 10,081 MB (~10.08 GB)** | **100%** | **其中 99.8% 均为构建产物与测试快照** | - |

---

## 三、为什么 GitHub 远程没有推送这些文件？

> [!NOTE]
> 这是完全正常且严格必须的！Git 通过根目录与 `android` 目录的 `.gitignore` 进行了过滤：
> 1. **`build/` 与 `.dart_tool/`**：属于本地编译的二进制中间缓存，带本机绝对路径，体积巨大（10GB）。若推送到 GitHub，仓库将臃肿不堪、无法协作；
> 2. **`android/app/yuyin-release.jks` 与 `android/key.properties`**：是 Release 正式签名私钥与密钥密码，绝对机密，严禁提交推送；
> 3. **`android/local.properties` 与 `.vscode/`、`.idea/`**：记录的是本机的 SDK 绝对路径与编辑器个人偏好，不能污染公网仓库；
> 4. **`log/` 下的 `*.log`**：属于本地调试运行日志。
>
> 远程 GitHub 只需保管源文件代码（仅十几 MB），任何人在其他电脑拉取代码后运行 `flutter pub get` 和 `flutter build` 即可重新编译生成。

---

## 四、技术改造实现方案

### 1. 升级构建脚本的自动清理机制

#### (1) `tool/build_debug_apk.bat`
- 读取 `pubspec.yaml` 获取当前版本号 `APP_VER`；
- 在输出最新 `YuYin_%APP_VER%_debug.apk` 后，扫描 `build\app\outputs\flutter-apk\YuYin_*_debug.apk`；
- 凡文件名不匹配当前版本号的旧版 debug 安装包，自动执行静默清理；
- 自动清理 `build\test_cache\` 测试快照目录；
- 控制台回显已清理的旧文件数量与保留的当前版本。

#### (2) `tool/build_release_apk.bat`
- 在编译并生成最新的 `YuYin_%APP_VER%_v8a.apk` 与 `YuYin_%APP_VER%_Universal.apk` 后；
- 扫描清理同目录下历史版本的 Release 安装包；
- 保证输出目录只包含当前生效的最新产物。

### 2. 新增工程一键瘦身脚本 `tool/clean_project.bat`

提供两种清理模式：
- **`.\tool\clean_project.bat quick`（或直接无参运行，日常极速瘦身，耗时约 1~2 秒）**：
  - 清理所有旧版本 APK 安装包；
  - 清理 `build\test_cache\`（测试快照）；
  - 清理 `.dart_tool\flutter_build\`（编译历史快照）；
  - 清理 `log\` 下临时日志；
  - 保留 Gradle 依赖缓存，下次编译依然享受增量加速。
- **`.\tool\clean_project.bat full`（全量深度重置）**：
  - 执行 `flutter clean`；
  - 清理 `build` 与 `.dart_tool` 缓存；
  - 自动执行 `flutter pub get` 重建依赖；
  - 彻底恢复到几十兆的纯净初始代码态。

---

## 五、验证与测试

1. 验证 `tool/clean_project.bat quick` 运行无误，查看清理后的磁盘空间释放数据；
2. 验证 `tool/build_debug_apk.bat` 与 `build_release_apk.bat` 能够正常执行编译并自动清理历史 APK；
3. 执行 `flutter test`（140 个测试用例全部通过）与 `flutter analyze`（0 warning/error）；
4. 统计清理前后的体积对比，向用户提供完整汇报。

