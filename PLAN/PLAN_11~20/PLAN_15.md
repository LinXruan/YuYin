# PLAN_15：实施 PLAN_14：实况图 RSC 解析与 B 宽限期（115）

## 背景

PLAN_14 已完成实况图问题的根因分析与方案设计：

- 分享页 B 的数据只有图片，顶层 `video` 是背景音乐；
- 真正的实况视频在主页面 `__pace_f` RSC 数据的 `images[0].video.playAddr`；
- RSC 是 `<id>:<tag><payload>` 多行流，旧 `scanPace` 解析方式错误，PLAN_13 又删除了它；
- B 在约 1 秒完成任务并停掉注入定时器，RSC 约 2.8 秒才可用，导致实况视频丢失。

本计划负责把 PLAN_14 的方案落地到 115 版本，并完成验证。

## 目标

1. 恢复正确的 RSC 行解析，并兼容 RSC 的 camelCase 字段；
2. B 的图片结果改为候选 + 3 秒宽限期，保留注入定时器，让 RSC 补充实况视频；
3. 单图、多图、视频、取消、超时行为不回归；
4. 版本升到 `1.0.0+115`。

## 实施步骤

### 1. JS：RSC 行解析

文件：`lib/services/js_script_builder.dart`

- 新增 `scanPace()`：
  - 正则提取 `self.__pace_f.push([1, "..."])` 的字符串；
  - 反转义后按 `\n` 拆行；
  - 每行取第一个 `:` 后的 body，必要时去掉 `I`/`T`/`$` 等 RSC tag；
  - 逐行 `JSON.parse`，成功则 `scanTree(value)`；
  - 返回是否找到 `__pace_f` 脚本。
- `S` 增加 `paceHref`、`paceDone`；href 变化和 `__douyinSnifferReset` 时重置；
- `tryExtractNow` 在静态源扫描后、动态 player/DOM 前调用 `scanPace()`；找到脚本或 `readyState === 'complete'` 后置 `paceDone`。

### 2. JS：camelCase 兼容

- `pickImage`：`img.url_list || img.urlList`；
- `pickBest`：`playAddr` 回退补 `video.width/height/dataSize`；
- `collectImages`：实况视频项补 `dataSize`；
- `collectVideos` 已兼容 `bitRateList`/`playAddr`/`playApi`，不改。

### 3. Dart：B 图片结果候选 + 宽限期

文件：`lib/services/douyin_sniffer.dart`

- 新增 `_kShareImageGrace = Duration(seconds: 3)`；
- 新增 `_pendingImageResult`、`_imageGraceTimer`；
- `_runShareFallback` 的图片分支改为 `_scheduleImageFallback(result, taskId)`，不立即完成；
- 宽限期到且任务仍活跃时，用 B 的图片完成；
- `_stopTimers` 取消宽限定时器并清空候选；
- 新任务、取消、超时、dispose 复用 `_stopTimers` 清理；
- 视频结果保持原有缓存逻辑。

### 4. 版本与文档

- `pubspec.yaml`、`lib/app_info.dart`、`README.md`、`CLAUDE.md`：`1.0.0+115`；
- `README.md` 技术要点补一句实况图 RSC 来源；
- 回填本计划验证结果。

## 涉及文件

- `lib/services/js_script_builder.dart`
- `lib/services/douyin_sniffer.dart`
- `pubspec.yaml`
- `lib/app_info.dart`
- `README.md`
- `CLAUDE.md`
- `PLAN/PLAN_15.md`

## 验证

- `flutter analyze`：`No issues found`
- `flutter test`：53 个测试全部通过
- `node --check`：注入 JS 语法通过
- `flutter build apk --debug`：构建成功
- 模拟器回归四类作品：
  1. 实况图：2/2，包含 `实况视频 (LIVE) 360x644`；
  2. 单图：1/1；
  3. 多图：3/3，不误加背景音乐；
  4. 视频：多档位正常；
  5. 取消/超时：宽限定时器不残留。

## 验证结果

- `flutter analyze`：No issues found
- `flutter test`：53 个测试全部通过
- `node --check`：注入 JS 语法通过
- `flutter build apk --debug`：构建成功
- APK：`build/app/outputs/flutter-apk/app-debug.apk`，aapt 校验 package=`com.debug.yuyin`、versionCode=`115`、versionName=`1.0.0`
- 模拟器回归（115，登录状态）：
  - 实况图：B 命中后等待，RSC 补充为 2 个资源，面板 `已选 2 / 2 项`，显示 `实况视频 (LIVE) 360x644`；
  - 单图：`已选 1 / 1 项`；
  - 多图：`已选 3 / 3 项`，未误加背景音乐视频；
  - 视频：`选择下载画质（共 10 个档位）`，最高 1024x576 / 1.7 Mbps；
  - 取消：日志在“已取消下载”后停止，宽限定时器未残留。
- 真机回归：待用户在真机确认（模拟器已全部通过）。
