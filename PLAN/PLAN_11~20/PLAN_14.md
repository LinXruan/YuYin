# PLAN_14：实况图视频解析修复：RSC 数据源与 B 兜底协调（115）

## 背景

114 版本分享页兜底 B 修复后，单图/多图正常，但**实况图只解析出 1 张图片，缺少 1 个实况视频**。用户确认 112_pl11 版本有概率能解析出实况视频。

### 已确认的根因

1. **分享页 B 的数据本身没有 live video**：实况图的 `_ROUTER_DATA.item_list[0]` 里 `images[0]` 只有 `uri/url_list/download_url_list/height/width`，没有 `video`；item 顶层 `video` 实际是背景音乐 mp3（`duration=0`、`bit_rate=null`、`ies-music-hj/*.mp3`）。因此 B 无论怎么解析都只能得到图片。
2. **主页面 `__pace_f` RSC 数据里有 live video**：主页面 `/note/{id}` 的 `self.__pace_f.push([1,"..."])` 中，`8:[...{"awemeId":"...","aweme":{"detail":...}}]` 包含完整的 aweme detail；其中 `images[0].video` 为：
   ```json
   {"width":360,"height":644,"duration":2900,"dataSize":272041,
    "playAddr":[{"src":"https://.../video/tos/...mp4"}, ...]}
   ```
   这是真正的实况视频，360x644、约 272KB。
3. **RSC 数据不是独立 JSON**：它是 `<id>:<tag><payload>` 的多行 flight 流，旧 `scanPace` 整块 `JSON.parse` 必然失败；PLAN_13 把 `scanPace` 删除后，这条唯一能拿实况视频的路径消失了。
4. **B 成功会提前结束任务**：B 在 ~1 秒完成并调用 `_finishWithItems` → `_stopTimers()`，而主页面 RSC 数据在 ~2.8 秒才可用；注入定时器被停掉，RSC 扫描没有机会执行。这正是“分享页兜底覆盖后续解析”。

### 临时验证结果

在 114 代码上禁用 B、加入正确 RSC 行解析并兼容 `urlList` 后，实况图成功解析：

- 日志：`图集解析: 1 项, 产出 2 个资源`、`解析成功：共发现 1 张图片、1 个视频`
- 选择面板：`已选 2 / 2 项`，显示 `实况视频 (LIVE) 360x644`
- 耗时：页面开始后约 2.8 秒

## 目标

1. 恢复并正确实现 `__pace_f` RSC 行解析，支持 camelCase 字段（`urlList`、`playAddr`、`dataSize`）；
2. B 的图片结果不再立即完成任务，改为候选/宽限期，让 RSC/A/C 有机会补充实况视频；
3. 保持单图、多图、普通视频、取消、超时行为不回归；
4. 版本升到 `1.0.0+115`。

## 方案

### 1. JS：正确的 RSC 行解析

文件：`lib/services/js_script_builder.dart`

- 恢复 `scanPace()`，逻辑：
  1. 用正则提取 `self.__pace_f.push([1, "..."])` 的字符串；
  2. `JSON.parse('"' + m[1] + '"')` 反转义；
  3. 按 `\n` 拆行，对每行取第一个 `:` 后的 body（行格式 `<id>:<tag><payload>`）；
  4. body 若以 `I`/`T`/`$` 等 RSC tag 开头，尝试去掉首字符再解析；
  5. 逐行 `JSON.parse`，成功则 `scanTree(value)`；
  6. 任一行命中目标作品并 `S.sent` 后停止。
- 每页只扫一次：`S` 增加 `paceHref`、`paceDone`，`href` 变化或 `__douyinSnifferReset` 时重置；找到 `__pace_f` 脚本或 `document.readyState === 'complete'` 后置 `paceDone`。
- 保留 PLAN_13 的静态源 `staticHref/staticReady/staticComplete` 门控；RSC 扫描放在静态源之后、动态 player/DOM 之前。
- 删除临时 `debugPace`、`PACE` 日志和 `paceLogged`。

### 2. JS：camelCase 兼容

RSC aweme detail 使用 camelCase，分享页使用 snake_case，需同时兼容：

- `pickImage`：`img.url_list || img.urlList`；
- `pickBest`：`playAddr` 回退时补 `video.width/height/dataSize`；
- `collectImages`：实况视频项补充 `dataSize`；
- `collectVideos` 已兼容 `bitRateList`/`playAddr`/`playApi`，不重复改。

### 3. Dart：B 图片结果改为候选 + 宽限期

文件：`lib/services/douyin_sniffer.dart`

新增常量与字段：

```dart
static const Duration _kShareImageGrace = Duration(seconds: 3);
DouyinShareResult? _pendingImageResult;
Timer? _imageGraceTimer;
```

`_runShareFallback` 中：

- 图片结果不再直接 `_finishWithItems`，改为 `_scheduleImageFallback(result, taskId)`：
  - 保存 `_pendingImageResult`；
  - 启动 `_imageGraceTimer = Timer(_kShareImageGrace, ...)`；
  - 宽限期到且任务仍活跃、completer 未完成时，用 B 的图片完成。
- 视频结果保持现有逻辑（缓存 `_shareVideoFallback`，不立即完成）。
- 日志区分“分享页兜底命中（等待实况补充）”与最终完成。

协调规则：

- 宽限期内 RSC/A/C 任一结果到达：正常 `_finishWithItems`，`_stopTimers()` 取消宽限定时器并清空候选；
- 宽限期到达仍无其他结果：用 B 的图片完成，保证普通单图/多图仍可用；
- `_stopTimers` 统一取消 `_imageGraceTimer` 并清空 `_pendingImageResult`；
- 新任务、取消、dispose、错误路径同样清理；
- B 的图片结果不会关闭 `_acceptMessages`，RSC 的 `type=result` 仍能进入。

### 4. 版本与文档

- `pubspec.yaml`、`lib/app_info.dart`：`1.0.0+115`；
- `README.md`、`CLAUDE.md` 同步版本；
- `README.md` 技术要点补一句“实况图通过主页面 RSC 数据补充 live video”；
- 新增 `PLAN/PLAN_14.md`，执行完回填验证结果。

## 涉及文件

**新增**
- `PLAN/PLAN_14.md`

**修改**
- `lib/services/js_script_builder.dart`
- `lib/services/douyin_sniffer.dart`
- `lib/services/douyin_share_api.dart`（如最终需要 live video 专用解析，保持只读确认）
- `pubspec.yaml`
- `lib/app_info.dart`
- `README.md`
- `CLAUDE.md`

## 验证

- `flutter analyze`：`No issues found`
- `flutter test`：现有 53 个测试全部通过
- `node --check`：提取后的注入 JS 语法通过
- `flutter build apk --debug`：构建成功
- 模拟器/真机回归：
  1. 实况图：选择面板出现 `已选 2 / 2 项`，包含 `实况视频 (LIVE) 360x644`；
  2. 单图：仍为 1 张图片，不因宽限期卡住；
  3. 多图：仍为 3 张图片，不误加背景音乐视频；
  4. 普通视频：多档位、下载正常；
  5. 取消/超时：宽限定时器不残留，日志正常停止；
  6. 连续两次解析：第二任务不继承第一任务的候选结果。

## 不在本次范围

- 重写整个 RSC 协议解析器；
- 将 B 图片与 RSC 结果按 URL 合并（当前规则是“其他来源优先，B 仅兜底”）；
- 实况图多图混排的进一步 UI 优化；
- 安全配置与历史页。

## 风险

- RSC 结构可能随抖音前端改版变化，解析器需保留失败静默与日志；
- 宽限期 3 秒是模拟器实测值（RSC 约 2.8 秒），真机可能更慢，需要按真机数据微调；
- 宽限期会让普通图片的弹出时间从 ~1 秒延后到最多 ~4 秒；
- RSC 扫描只做一次，若数据晚于 `complete` 才注入，可能仍错过，需要网络/静态源兜底。

## 验证结果

已由 `PLAN_15.md` 实施并验证，结果见该计划。
