# PLAN_13：核心抓取链路优化：修复分享页 Cookie、移除 RSC 噪音（114）

## 背景

113 真机日志（`113_log/`）暴露三个问题：

1. **分享页兜底 B 100% 失败**：日志固定出现“分享页未返回作品数据，可能触发风控”。curl 复现确认：无 Cookie 时 iesdouyin 返回风控验证壳；先 GET 拿到 `Set-Cookie: ttwid=...`，再带 Cookie 重试即可返回含 `videoInfoRes` 的分享页，现有 `DouyinShareApi.parseShareHtml` 能解析。根因是 Dio 请求从不携带 ttwid。
2. **`__pace_f` 每次“非 JSON，已跳过”**：Next.js RSC flight 是带 `id:` 前缀的多行流，不是独立 JSON；8 份历史日志 0 产出。
3. **静态数据源重复扫描**：注入脚本每 1.2 秒把 `_ROUTER_DATA`、`#RENDER_DATA`、`__INIT_PROPS__` 全树重扫，且 `scanPace` 纯属空转。

本次范围：**修复 B + 删除 scanPace + Dart 内去重**；版本升到 **`1.0.0+114`**。

## 目标

1. B 增加 ttwid 获取、缓存与一次重试，图文有机会不切 WebView 就完成；
2. 删除 `scanPace`，消除无效扫描与日志噪音；
3. 静态数据源按页面就绪状态最多扫两次，动态 player/DOM 扫描保留；
4. 合并 Dart 内重复工具函数与分享页 URL；
5. 补 Cookie 重试与纯函数测试，现有 43 个测试保持通过；
6. 版本升到 `1.0.0+114`。

## 方案

### 1. 修复 B：ttwid 获取与重试

文件：`lib/services/douyin_share_api.dart`

- 新增 `_cookieHeader` 跨任务缓存；
- `fetchShareItem` 最多两次请求：带缓存 Cookie 请求；解析失败且响应 `Set-Cookie` 使 Cookie 变化时重试一次；带缓存 Cookie 仍失败且无新 Cookie 时清空缓存；
- 请求设置 `validateStatus: (_) => true`，确保 4xx 也能读取 `Set-Cookie`；
- `set-cookie` 用 `response.headers['set-cookie']` 的 List，只取第一个 `;` 前的 `name=value`，不按逗号拆；
- 新增 `parseSetCookies`、`mergeCookieHeader` 纯函数（同名大小写不敏感覆盖，限制 20 项 / 4KB，值不写日志）；
- 新增 `DouyinShareCancelledException` 区分外部取消；`fetchShareItem` 增加 `totalTimeout`（10 秒），超时取消 token 并抛普通分享页异常；
- 新增 `sharePageUrl(awemeId)`，B 与 C 共用。

`lib/services/douyin_sniffer.dart`：

- 新增 `_kShareFallbackBudget = Duration(seconds: 10)` 并传入 `fetchShareItem`；
- `_runShareFallback` 先捕获 `DouyinShareCancelledException` 直接 return；
- C 路径改用 `DouyinShareApi.sharePageUrl(awemeId)`。

### 2. JS 抓取链路瘦身

文件：`lib/services/js_script_builder.dart`

- 删除 `scanPace` 函数与 `tryExtractNow` 中的调用；
- `S` 增加 `staticHref`、`staticReady`、`staticComplete`；
- 静态源在 `document.readyState !== 'loading'` 后扫第一次；若首次已是 `complete` 同时置 `staticComplete`；之后变为 `complete` 时再补扫一次（每页最多两次）；
- 静态源顺序改为 `_ROUTER_DATA` → `#RENDER_DATA` → `__INIT_PROPS__`；
- `scanPlayerData` 与 `scanPlayer` 仍每 1.2 秒执行；
- `__douyinSnifferReset` 同步重置新字段。

### 3. Dart 内去重

- 新增 `lib/utils/parse_utils.dart` 的 `positiveInt`；
- `lib/models/media_item.dart` 与 `lib/services/douyin_share_api.dart` 改用它，删除两份重复实现；
- `pickBestVideo` 简化为 `parseVideoTiers` 首项；
- 分享页 URL 统一走 `DouyinShareApi.sharePageUrl`。

### 4. 版本与文档

- `pubspec.yaml`、`lib/app_info.dart`、`README.md`、`CLAUDE.md`：`1.0.0+114`；
- README 的 `lib/utils` 结构补 `parse_utils.dart`，测试数量按实际结果更新。

## 涉及文件

**新增**
- `PLAN/PLAN_13.md`
- `lib/utils/parse_utils.dart`
- `test/parse_utils_test.dart`

**修改**
- `lib/services/douyin_share_api.dart`
- `lib/services/js_script_builder.dart`
- `lib/services/douyin_sniffer.dart`
- `lib/models/media_item.dart`
- `test/douyin_share_api_test.dart`
- `pubspec.yaml` / `pubspec.lock`
- `lib/app_info.dart`
- `README.md`
- `CLAUDE.md`

## 验证

- `flutter analyze`：`No issues found`
- `flutter test`：现有 43 个 + 新增用例全部通过
- `flutter build apk --debug`：构建成功
- 真机回归：单图 B 出现“分享页兜底命中”且无 `__pace_f` 日志；多图 `_ROUTER_DATA` 正常；视频多档位正常；连续两次解析复用 Cookie；取消/超时行为正常；下载保存正常

## 验证结果

- `flutter analyze`：No issues found
- `flutter test`：53 个测试全部通过（原有 43 + 新增 10）
- `flutter build apk --debug`：构建成功（Gradle assembleDebug 约 16 秒）
- APK：`build/app/outputs/flutter-apk/app-debug.apk`
- aapt 校验：package=`com.debug.yuyin`，versionCode=`114`，versionName=`1.0.0`，application-label=`余音`
- 真机回归：待用户重新连接设备后安装测试（B 应出现“分享页兜底命中”，日志不再出现 `__pace_f`；多图/视频/取消/超时/连续解析待验证）
