# PLAN_69：修复主页/多作品套壳链路的保存页小 bug（版本 1.5.5+183）

> 目标：修复四个由「多作品/单作品直接套壳主页保存页三层结构」引起的小 bug，不改变 Author → Work → Resource 分层约束传播架构。
> 原则：加载态只覆盖准备阶段；预载结果构造时即物化；画质面板改为会话驱动、点选即写入；删除旧的本地副本实现。

---

## 一、根因分析

### 1.1 进入 resource 页后 work 层加载态不停

`lib/widgets/save_page/middle/flow/middle_work_open_flow.dart:8-13`

```dart
_refresh(() => _openingIndex = index);
try {
  await callback(_rows[index].url, index);   // 等的是子页面整个存活期
} finally {
  if (mounted) _refresh(() => _openingIndex = null);
}
```

`lib/pages/parse/flow/common/save_page_flow.dart:38,42` 内部 `await _pickWorkTier(...)`、`await ImagePreviewSheet.show(...)`，Future 在子页面关闭时才完成。视频档位面板 `mainAxisSize.min`、最高 0.7 屏（`video_quality_sheet.dart:171-176`），work 层 82% 面板上方可见，转圈在画质页打开期间持续运行。

顶层作者格子同构：`lib/widgets/save_page/top/flow/top_sheet_action_flow.dart:8-13` 等待整个中层页面关闭（`home_parse_flow.dart:207`）。

### 1.2 多作品解析重复预加载

`lib/services/multi_work/multi_work_extractor.dart:81` 已把完整解析结果写入 `SaveWorkItem.parsedResult`；但 `lib/services/selection/save_selection_session.dart:94` 的 `multiWork` 工厂经 `_createWork`（:258）构造节点时只读 `work.kind`，节点 `_parsed` 恒为 `false`。`lib/pages/parse/flow/common/save_page_flow.dart:13` 判断 `row.parsed` 为假，再次 `sniffVideoUrl`。

连带：`SessionWorkPreparer.prepare`（`session_work_preparer.dart:19`）与 `/api/save/works`（`save_works_handler.dart:58`）同样重复解析。

只有 `singleWork` 工厂在 `save_selection_session.dart:140` 手动 `ingest`，说明「预载物化」逻辑存在但只覆盖单一来源。

### 1.3 单链接视频底部按钮显示「返回」

`lib/pages/parse/flow/single/single_parse_flow.dart:230` → `save_page_flow.dart:74` → `VideoQualitySheet.showSelect`，底部按钮硬编码「返回」（`video_quality_sheet.dart:236-241`）。单链接时该面板就是最终确认页。

### 1.4 画质必须点「返回」才生效

`VideoQualitySelectSheet` 自存 `_selectedIndex`（`video_quality_sheet.dart:147,229`），点选只改本地副本，`Navigator.pop` 后由 `save_page_flow.dart:78` 才 `session.setTier`。违反「一个状态只存一份」，也导致必须返回确认。

---

## 二、目标语义

| # | 行为 | 判定 |
| --- | --- | --- |
| 1 | 点击 work 缩略图右下角，解析准备完成后立即停止该格加载态 | 子页面压栈后 work 层无 `CircularProgressIndicator` |
| 2 | 顶层作者格子进入中层后同样立即停止加载态 | 同上 |
| 3 | 多作品会话语义：`SaveWorkItem.parsedResult` 非空即视为已解析 | `session.workOf(url)!.parsed == true`，`tiers/resources` 已物化 |
| 4 | 多作品进入 resource 页不再二次嗅探 | `_openWorkDetail` 不调用 `sniffVideoUrl` |
| 5 | 单作品视频 resource 面板底部按钮为「保存选中项 (1)」+ 保存图标 | Widget 测试 / uiautomator |
| 6 | 主页/多作品视频 resource 面板底部按钮为「返回」+ 返回图标 | Widget 测试 |
| 7 | 点击任意画质档位立即写入会话，不依赖底部按钮 | 点选后 `selectedTier` 立即变化 |
| 8 | 底部按钮只负责关闭面板，不承担确认语义 | 关闭前后 `selectedTier` 不变 |
| 9 | 画质面板勾选态由会话派生，不再持有本地副本 | 删除 `_selectedIndex` |
| 10 | 不改变选择轴、约束传播、保存解算与主页按需解析 |

---

## 三、新增文件清单

| 文件 | 角色 | 预估行数 |
| --- | --- | --- |
| `lib/widgets/save_page/bottom/widget/video_tier_picker_sheet.dart` | resource 层画质档位面板（会话驱动、点选即写） | 约 130 |
| `lib/widgets/save_page/bottom/widget/quality_badge.dart` | 「最高画质」原子标签，供两个画质面板共用 | 约 32 |
| `test/plan_69_save_page_test.dart` | 预载物化、加载态、点选即写、文案可配置回归 | 约 230 |

目录 `bottom/widget/` 届时 4 个文件（bottom_media_tile、video_quality_sheet、video_tier_picker_sheet、quality_badge），符合 2~8。

---

## 四、删除清单

| 位置 | 行数 | 理由 |
| --- | --- | --- |
| `video_quality_sheet.dart` 的 `VideoQualitySelectSheet` | 约 115 | 被会话驱动的新面板取代，且持有第二份选择状态 |
| `video_quality_sheet.dart` 的 `VideoQualitySheet.showSelect` | 约 14 | 调用点改为新面板，无兼容壳 |
| `video_quality_sheet.dart` 的 `_HighestQualityBadge` | 约 28 | 提升为共用 `quality_badge.dart` |
| `save_selection_session.dart:140` 的 `session.ingest(work.url, parsed)` | 1 | 由 `_createWork` 统一消费 `parsedResult` |
| `save_page_flow.dart` 的旧 `_pickWorkTier` | 约 28 | 拆分为「非阻塞呈现」与「单作品确认」两个职责 |

删除后全库 grep 确认无 `showSelect` / `VideoQualitySelectSheet` / `_selectedIndex` 残留。

---

## 五、实现要点

### 5.1 预载物化（`save_selection_session.dart`）

`_createWork` 构造节点后统一消费 `parsedResult`：

```dart
final node = work.isVideo ? _VideoWorkNode(...) : _MediaWorkNode(...);
final parsed = work.parsedResult;
if (parsed != null) {
  final cover = work.coverUrl.trim();
  node.work = work.copyWith(
    coverUrl: cover.isEmpty ? (parsed.coverUrl ?? '') : cover,
  );
  node.ingest(parsed);
}
return node;
```

`singleWork` 工厂改为 `_createWork(work.copyWith(parsedResult: parsed), ...)`，删除额外的 `session.ingest`。

### 5.2 非阻塞呈现（`save_page_flow.dart` / `home_parse_flow.dart`）

- 拆出 `_presentWorkTier`、`_presentWorkMedia`：调用 `show(...)` 后立即返回，关闭后的日志用 `unawaited(future.then(...))`。
- `_openWorkDetail` 只等待解析准备；面板压栈即返回，work 层 `finally` 当帧清 `_openingIndex`。
- `_openAuthorWorks` 改为 `unawaited(MiddleMultiWorkSheet.show(...).then(...))`，顶层作者格子同帧停止加载。
- 单作品保留可等待入口 `_pickSingleTier`，供 `_chooseSingleWork` 取得确认结果。

### 5.3 画质面板（新文件）

- `VideoTierPickerSheet` 接收 `session`、`workUrl`、`tiers`、`actionLabel`、`actionIcon`。
- `ListenableBuilder` 监听会话，勾选态由 `session.workOf(workUrl)!.selectedTier` 现算。
- 点选调用 `session.setTier(workUrl, item.url)`；底部按钮 `Navigator.pop(context, true)`。
- 键位：`video_tier_option_$index`、`video_tier_action_button`，保留无障碍语义。

### 5.4 文案与图标

| 入口 | actionLabel | actionIcon |
| --- | --- | --- |
| 主页/多作品（work → resource） | `返回` | `Icons.arrow_back_rounded` |
| 单作品视频（最终确认） | `保存选中项 (1)` | `Icons.save_alt` |

---

## 六、执行步骤与验证

1. 写 PLAN_69，创建两个新组件与测试文件。
2. 修改会话工厂、解析流程、单作品流程，删除旧面板与旧入口。
3. `flutter analyze` 0 issues。
4. `flutter test` 全绿（含新增用例）。
5. 全库 grep：`showSelect`、`VideoQualitySelectSheet`、`_selectedIndex`、`_pickWorkTier` 无残留。
6. 版本改 `1.5.5+183`（`pubspec.yaml`、`lib/app_info.dart`），同步 `AGENTS.md` 现状。
7. 启动带界面模拟器（`tool/launch_emulator.py`），编译并安装 Debug：
   - `selection-load` mock（`video:true`）→ `selection-state` 校验 `parsed`、`tiers`；
   - `selection-quality` / `selection-tier` / `selection-verify` 校验画质写入与一致性；
   - `uiautomator dump` 校验 work 层格子、resource 面板键位与「返回」按钮；
   - 真机/模拟器手工烟测：主页、多作品、单链接三条链路均可进入/返回且无转圈残留。
8. Release 构建：`tool/build_release_apk.bat all`，安装 v8a 到模拟器做启动烟测。

---

## 七、验收清单

- [ ] 多作品会话构造后 `parsed == true`，档位/资源已物化。
- [ ] 从多作品 work 进入 resource 不再触发第二次 `sniffVideoUrl`。
- [ ] work 层加载态在 resource 页压栈当帧清除。
- [ ] 顶层作者加载态在中层压栈当帧清除。
- [ ] 单链接视频面板底部为「保存选中项 (1)」。
- [ ] 主页/多作品视频面板底部为「返回」。
- [ ] 点选档位立即改变 `selectedTier`，不点按钮也生效。
- [ ] 底部按钮只关闭面板，不写状态。
- [ ] `flutter analyze` 0、`flutter test` 全绿。
- [ ] 版本 1.5.5+183；Release v8a/Universal 构建成功、启动无崩溃。

---

## 八、风险与回退

| 风险 | 对策 |
| --- | --- |
| 构造时物化改变初始 `selection` | `ingest` 仍按 `defaultSelected` / 现有 `selectionState` 物化；补默认全选/全不选用例 |
| 多作品资源 URL 过期仍复用预载 | 预载来自本次解析、秒级内使用，与主页「按需解析」语义一致；不额外缓存跨会话 |
| 非阻塞呈现后关闭日志丢失 | `.then` 内补日志，`mounted` 守卫 |
| 单作品视频误关面板导致取消 | `show` 返回 `null` 视为取消，与旧行为一致 |
| 档位面板点选重构影响画质显示 | 勾选态改由 `selectedTier` 派生，等价于旧索引；保留 PLAN_68 过滤与单档位规则 |
| 回退 | 本次改动集中在 5 个业务文件 + 2 个新组件，可直接 revert 提交 |
