# PLAN_42：历史记录操控逻辑优化与界面精细化 (版本 1.4.0+149)

## 一、需求背景与目标

在 PLAN_41 完成历史记录基础设施、全文检索与交互联动的建设后，针对实机交互反馈进行 4 项关键操控逻辑与视觉细节的升级重构：

1. **移除顶部“选择”按钮**：常规状态下顶部操作栏更简洁，仅保留“清空”按钮（有数据时），多选模式改为通过“长按卡片”原生触发；
2. **退出多选模式改用安卓返回键**：移除多选模式下的“完成”胶囊按钮，接入 Android 原生返回手势与实体键拦截（`PopScope`），实现自然流畅的退出体验；
3. **视觉优化（移除勾选框）**：进入多选模式后，去除卡片左侧占位的 `Checkbox` 勾选框，避免列表内容水平跳动，选中状态纯通过主题色高光边框（1.5dp）与半透明主题强调背景变色予以清晰反馈；
4. **新增搜索框下方提示栏**：在至少存在 1 条历史记录时，于搜索框下方展示一行轻量提示卡片，样式严格对齐 PLAN_22 解析页的未登录提示浮窗（自适应浅色/暗色、高光图标、柔和边框与背景），引导用户“长按进入选择模式”。

---

## 二、系统设计与技术细节

```mermaid
flowchart TD
    subgraph HistoryPage_Interaction["历史记录交互生命周期"]
        Normal["常规模式 (!isSelectionMode)"] -->|长按任意卡片| EnterSelect["进入多选模式 (isSelectionMode = true)"]
        EnterSelect -->|将该卡片加入 _selectedIds| Selected["卡片呈现高亮边框与强调底色"]
        Normal -->|点击任意卡片| JumpParse["触发 onSelectRecord -> 切换解析 Tab 并回填链接"]
        
        EnterSelect -->|点击任意卡片| ToggleSelect["切换该卡片选中/取消状态"]
        EnterSelect -->|点击【全选/取消全选】| BulkSelect["批量全选或反选全部条目"]
        EnterSelect -->|点击【删除(n)】| ConfirmDel["二次确认弹窗 -> 批量删除"]
        EnterSelect -->|按 Android 返回键 / 侧滑返回| PopScopeIntercept["PopScope 拦截 pop 事件"]
        PopScopeIntercept --> ExitSelect["退出多选模式 (isSelectionMode = false, 清空选中)"]
    end

    subgraph PromptBanner["搜索框下方提示条"]
        CheckCount{"存在 >= 1 条历史且非多选态?"}
        CheckCount -->|否| HideBanner["不渲染 (SizedBox.shrink)"]
        CheckCount -->|是| ShowBanner["渲染 PLAN_22 双模配色提示条"]
        ShowBanner --> Content["图标 + '长按进入选择模式' + 关闭钮"]
    end
```

### 1. `PopScope` 返回键拦截逻辑
- 使用 Flutter 官方推荐的 `PopScope(canPop: !_isSelectionMode, onPopInvokedWithResult: ...)`；
- 当 `_isSelectionMode == true` 时，`canPop` 为 `false`，返回手势不会退出应用，而是重置 `_isSelectionMode = false` 与 `_selectedIds.clear()`；
- 当 `_isSelectionMode == false` 时，`canPop` 为 `true`，系统正常退出或返回上级。

### 2. 卡片视觉与手势绑定
- 移除 `_HistoryCard` 内部的 `Checkbox`；
- `onTap`：若处于多选模式，切换选中状态；若非多选模式，触发作品载入解析；
- `onLongPress`：若非多选模式，进入多选模式并选中当前项，辅以触感震动；若已在多选模式，切换当前项选中状态。

### 3. PLAN_22 提示栏样式规范继承
- 配色方案（与 `lib/pages/parse_page.dart` 中 `_LoginPromptBanner` 保持一致）：
  - 浅色模式：背景 `theme.colorScheme.primaryContainer` (alpha 0.28)，边框 `theme.colorScheme.primary` (alpha 0.25)，文字 `theme.colorScheme.onSurface`；
  - 暗色模式：背景 `#261F22`，边框 `#7B2949` (alpha 0.6)，高光图标 `#FFB0C8`，文字 `#ECE0E2`；
- 内容：“长按进入选择模式”，右侧提供轻触关闭按钮。

---

## 三、文件修改清单

| 序号 | 文件路径 | 修改类型 | 说明 |
| :--- | :--- | :--- | :--- |
| 1 | `pubspec.yaml` | MODIFY | 版本号提升至 `1.4.0+149` |
| 2 | `lib/app_info.dart` | MODIFY | 版本常量更新为 `1.4.0+149` |
| 3 | `GEMINI.md` / `CLAUDE.md` | MODIFY | 维护守则版本同步更新 |
| 4 | `lib/pages/history_page.dart` | MODIFY | 移除选择/完成按钮，接入 PopScope，移除勾选框，新增搜索框下方提示栏 |
| 5 | `test/history_page_test.dart` | MODIFY | 更新 Widget 测试用例适配长按进入多选、PopScope 退出以及提示栏呈现 |

---

## 四、验证计划

1. `flutter analyze` 静态检查确保 0 issues；
2. `flutter test` 确保工程内全部测试用例（包括修改后的 `history_page_test.dart`）全绿；
3. 模拟器实机功能与视觉验证：
   - 确认历史页顶部无“选择”按钮，仅保留“清空”；
   - 确认搜索框下方出现 PLAN_22 质感的提示框；
   - 长按卡片进入多选模式，确认卡片边框高亮变色、无小勾选框；
   - 确认多选模式顶部无“完成”按钮，按 Android 返回键能成功退出多选模式。

