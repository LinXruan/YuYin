# PLAN_68：画质过滤保留全量最低档与单档位修正（版本 1.5.5+182）

> 目标：修复「画质标签切最低后底层回填最高」与「手动选最后一档却显示混合」两个 bug；不改变分层传播架构。
> 原则：只修画质过滤与派生规则；删除优先；新增调试接口便于 adb/REST 验证。

---

## 一、根因

### 1.1 过滤把全量最低档隐藏，底层画质页回填最高

`lib/utils/download_settings_store.dart:212-246` 的 `filterHighestQualityPerResolution` 只保留每个分辨率下码率最高的档位：

```dart
for (final item in sorted) {
  final key = normalizeResolutionKey(item);
  if (key == null) { result.add(item); continue; }
  if (seenResolutions.add(key)) result.add(item);
}
```

全量最低档（规范排序最后一档）往往与更高档同分辨率，因此被过滤掉。

`lib/pages/parse/flow/common/save_page_flow.dart:62-72`：

```dart
final tiers = VideoQualityUtils.displayTiers(row.tiers); // 已过滤
final current = row.selectedTier;
initialItem = tiers.firstWhere(
  (tier) => tier.url == current.url,
  orElse: () => tiers.first, // 当前档位被隐藏 -> 回退最高
);
```

标签切 `lowest` 后，`selectedTier` 是全量最后一档，但不在 `displayTiers` 中，底层初始值回退到第一档（最高）。用户点“返回”后 `setTier` 写入最高档，表现为“标签点了没用”。

### 1.2 手动选最后一个可见档位不等于全量最低档

过滤后的最后一项可能是某个中间档（例如 `1080P 431k`），并非全量排序最后的 `720P 257k`。

`lib/models/save_page/selection/quality_preference.dart:102-117` 按全量列表判断：

```dart
if (sortedTiers.length == 1 || index == 0) return highest;
if (index == sortedTiers.length - 1) return lowest;
return mixed;
```

因此手动选择“可见的最后一行”会落到 `mixed`，work 标签显示混合画质。

### 1.3 单档位时 edge(lowest) 仍显示 lowest

`lib/models/save_page/selection/quality_preference.dart:38-46`：

```dart
if (!selected || sortedTiers.isEmpty) return none;
return edge == highest ? highest : lowest;
```

没有优先判断“只有一档”，违反「画质 tag 只有一种时认为 highest」的规则。

---

## 二、目标语义

1. `filterHighestQualityPerResolution` 在保留每个分辨率最优档位后，**额外保留全量规范排序的最后一档**。
2. “最后一档”定义为 `VideoQualityUtils.sortTiers(items).last`（先按码率、再按体积从高到低），与 `QualityPreference` 的 highest/lowest 判断使用同一排序。
3. 过滤结果不得产生重复档位；未知分辨率、单档位、最低档本来就是某分辨率最优项时不重复追加。
4. 画质标签 `lowest` 解析到全量最后一档；底层画质页必须能显示并回填它。
5. 手动选择全量最后一档后，work 标签必须是 `lowest`，不是 `mixed`。
6. 只有一档时，无论 `edge(highest)` 还是 `edge(lowest)`，显示态均为 `highest`。
7. 不改变选择轴、传播规则、保存解算和现有 UI 交互。

---

## 三、修改文件清单

| 文件 | 变更 | 预估行数 |
| --- | --- | --- |
| `lib/utils/download_settings_store.dart` | 过滤结束后追加全量最后一档，去重 | 310（+8） |
| `lib/models/save_page/selection/quality_preference.dart` | `edge` 单档位优先返回 highest | 130（+2） |
| `lib/services/selection/debug/quality_options_snapshot.dart` | 新增全量/过滤后档位只读快照 | 约 60 |
| `lib/services/selection/debug/selection_debug_bridge.dart` | 新增 `qualityOptions` 只读方法 | 250（+10） |
| `lib/services/bridge/handler/save/selection_handler.dart` | 新增 GET `/api/selection/quality-options` | 250（+12） |
| `tool/agent_bridge.ps1` | 新增 `quality-options` 指令 | +10 |
| `DEBUG.md` | 记录新接口与过滤语义 | +12 |
| `test/plan_68_quality_filter_test.dart` | 新增过滤/回填/单档位回归 | 约 180 |
| `test/plan_67_quality_test.dart` | 补充单档位 edge(lowest) 断言 | 160（+10） |

无删除文件；不新增业务分层目录。

---

## 四、实现要点

### 4.1 过滤器

在 `filterHighestQualityPerResolution` 的循环结束后：

```dart
final lowest = sorted.last;
if (!result.any((item) => item.url == lowest.url)) {
  result.add(lowest);
}
```

- `sorted` 已按规范顺序从高到低排列，`last` 即全量最低档。
- 结果顺序保持高到低，最低档追加在末尾；`displayTiers` 之后还会再次 `sortTiers`，顺序稳定。
- 若最低档已在 `result`（例如它是某分辨率唯一档），不重复。
- 未知分辨率原本全部保留，不会重复。

### 4.2 单档位

`EdgeQualityPreference.indicator`：

```dart
if (!selected || sortedTiers.isEmpty) return QualityIndicator.none;
if (sortedTiers.length == 1) return QualityIndicator.highest;
return edge == QualityEdge.highest
    ? QualityIndicator.highest
    : QualityIndicator.lowest;
```

`SpecificQualityPreference.indicator` 已有 `sortedTiers.length == 1 → highest`，保持不变。

### 4.3 调试接口

新增只读端点：

`GET /api/selection/quality-options?workUrl=<url>`

返回：

```json
{
  "success": true,
  "workUrl": "...",
  "onlyHighestQualityPerResolution": true,
  "selectedTier": "...",
  "quality": "lowest",
  "full": [{"url": "...", "resolution": "...", "bitRate": 0}],
  "display": [{"url": "...", "resolution": "...", "bitRate": 0}]
}
```

用途：在 adb/REST 调试中直接确认“显示列表是否包含全量最后一档”，不需要截图。

---

## 五、执行步骤

1. 修改过滤器和单档位派生。
2. 新增 `qualityOptions` 调试桥与端点，更新 `agent_bridge.ps1`、`DEBUG.md`。
3. 新增 `plan_68_quality_filter_test`：
   - 11 档重复分辨率：过滤后最后一档 == 全量最后一档；
   - 过滤关闭：全量档位全部保留；
   - 最低档已存在：不重复；
   - 单档位 edge(lowest) → highest；
   - 标签 lowest 后 `display` 包含 `selectedTier`；
   - 选中 display 最后一档 → quality lowest。
4. 更新 `plan_67_quality_test` 单档位断言。
5. `flutter analyze` 0；`flutter test` 全绿。
6. 版本改为 `1.5.5+182`（`pubspec.yaml`、`lib/app_info.dart`），更新 `AGENTS.md` 现状。
7. 构建 Debug，安装到模拟器，使用 REST 验证：
   - `selection-load mock` / 真实单视频；
   - `select-quality work <url> lowest`；
   - `quality-options` 检查 `display.last == full.last`；
   - `select-tier` 选择 `display.last`，检查 `quality=lowest`；
   - `selection-verify` 返回 consistent；
   - 单档位场景检查 highest。
8. 构建 Release v8a/Universal，安装并启动 `com.release.yuyin` 做无崩溃烟测。
9. 提交：`182_pl68：修复画质过滤丢失最低档与单档位显示`。

---

## 六、验收清单

- [ ] 开启“仅显示最高画质”时，过滤结果始终包含全量规范排序最后一档。
- [ ] 过滤结果无重复 URL。
- [ ] 画质标签切 `lowest` 后，`selectedTier` 在全量最后一档，且该档在 `display` 中。
- [ ] 底层画质页初始值等于 `selectedTier`，不再回退到最高档。
- [ ] 手动选择 `display.last` 后，work 标签为 `lowest`，不是 `mixed`。
- [ ] 单档位 + edge(highest/lowest) 均显示 `highest`。
- [ ] 过滤关闭时行为不变。
- [ ] `flutter analyze` 0、`flutter test` 全绿。
- [ ] `/api/selection/quality-options` 可在模拟器返回 `full/display/selectedTier`。
- [ ] `/api/selection/verify` 在关键路径后均为 consistent。
- [ ] 版本 1.5.5+182，Release v8a/Universal 构建成功且无启动崩溃。

---

## 七、风险与回退

| 风险 | 对策 |
| --- | --- |
| 过滤器全局生效，影响单作品/保存页所有画质列表 | 保留最高档逻辑不变，只追加最低档；补过滤关闭、单档位、未知分辨率测试 |
| “最低”按体积而非码率定义导致与规范排序不一致 | 统一使用 `sortTiers(items).last`，不单独按 dataSize 选 |
| 过滤结果重复 | 按 URL 去重后再追加 |
| 底层仍回填最高 | `quality-options` 端点直接检查 `display` 是否包含 `selectedTier` |
| 单档位旧断言冲突 | 以「单档位 = highest」为准更新测试 |
| 大改回滚 | 本次只改 2 个业务文件 + 调试/测试；可直接 revert 本次提交 |
