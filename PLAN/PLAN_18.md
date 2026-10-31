# PLAN_18：输入框滚动条样式与位置调优方案（版本 1.0.0+120）

## 一、需求背景与目标

在 PLAN_17 中，我们为输入框实现了固定高度 120dp 以及滚动浏览能力。但在实机与模拟器测试中发现，Flutter 原生 `Scrollbar` 组件存在以下体验缺陷：
1. **遮挡边框**：原生滚动条贴在最右边缘，直接叠在 `OutlineInputBorder` 的边框线上，在顶部与底部还会压在圆角拐角处；
2. **行程与位置不准**：原生滚动条计算基于外层父容器尺寸，未扣除 `InputDecoration` 内部边框与内边距，导致滑到底部时滑块却停在中间；
3. **缺少自动渐隐**：原生组件在配置 `thumbVisibility: true` 后一直常驻；
4. **滑块长度未随文本量动态响应**；
5. **无需拖拽功能**：用户仅通过滑动文本区域浏览，滚动条只需作为纯粹、精致的视觉指示器。

基于用户的 5 点明确要求，我们将在版本 **`1.0.0+120`** 中针对输入框滑动条进行专门重构与数学建模计算。

---

## 二、详细技术方案

### 1. 结构重构：从原生 Scrollbar 升级为定制滚动指示器（Visual Scroll Indicator）
- 原生 `Scrollbar` 是通用组件，无法微调其相对子组件边框的上下/左右内缩边距，也无法修正 `TextField` 装饰层与内容层的计算偏差。
- 采用 **`Stack` + `NotificationListener<ScrollNotification>` + `Positioned` + `IgnorePointer`** 架构：
  ```
  SizedBox(height: 120)
  └── Stack
      ├── TextField（监听手势、接收输入与自然滚动）
      └── Positioned（定制悬浮指示条，IgnorePointer 穿透点击）
  ```

### 2. 核心要求对应实现

#### 要求 1：向左微调，防止遮挡边框
- 右边距设为 `right: 7.0`，滑块宽度设为 `3.0` dp，边缘为 `BorderRadius.circular(1.5)`。
- 完美避开 `OutlineInputBorder`（粗细约 1.0dp ~ 2.0dp）的线条区域，悬浮于输入框右侧内壁，保持清晰的留白。

#### 要求 2：不滑动时自动渐隐（Fade In / Out）
- 采用 `AnimatedOpacity(duration: Duration(milliseconds: 250), opacity: _showScrollIndicator ? 1.0 : 0.0)`；
- 通过 `NotificationListener<ScrollNotification>` 监听滚动事件：
  - 用户触发滚动瞬间：立即 `setState(() => _showScrollIndicator = true)`；
  - 滚动停止后：启动 1.2 秒定时器 `_hideScrollTimer`，超时后平滑淡出隐藏；
  - 若文本不足一屏（`maxScrollExtent <= 0`），始终保持完全隐藏（`opacity = 0.0`）。

#### 要求 3：文本量越大，滑块长度越短
- 轨道有效高度：$H_{track} = 120 - P_{top} - P_{bottom}$（设定 $P_{top} = 8.0, P_{bottom} = 8.0$，则 $H_{track} = 104.0$）；
- 视口总内容高度：$H_{total} = ViewportDimension + MaxScrollExtent$；
- 视口可视比例：$Ratio = (ViewportDimension / H_{total})$；
- 滑块高度：$H_{thumb} = (H_{track} \times Ratio)$，限制在 `[20.0, H_{track} - 12.0]` 范围内；
  - 当文本为 4~5 行刚好溢出时：滑块较长（约 60~80dp）；
  - 当文本达到数千字时：滑块自适应缩短至最小 `20.0dp`；
  - 完全符合“粘贴的文本量越大滑动条本身长度越短”。

#### 要求 4：精准行程与边框避让计算
- **边框粗细与圆角避让**：
  - 顶部安全内缩：$P_{top} = 8.0$ dp；
  - 底部安全内缩：$P_{bottom} = 8.0$ dp；
- **位置计算公式**：
  - 滚动进度：$Progress = (ScrollPixels / MaxScrollExtent).clamp(0.0, 1.0)$；
  - 滑块移动总行程：$TravelDistance = H_{track} - H_{thumb}$；
  - 滑块垂直位置：$ThumbTop = P_{top} + Progress \times TravelDistance$；
- **边界验证**：
  - **滑到最顶（Progress = 0.0）**：$ThumbTop = 8.0$ dp，滑块顶部距容器外檐 8dp，完全不接触或遮挡上边框；
  - **滑到最底（Progress = 1.0）**：$ThumbTop = 8.0 + (104.0 - H_{thumb}) = 120.0 - 8.0 - H_{thumb}$，即滑块底部刚好落在 $120.0 - 8.0 = 112.0$ dp，精准对应粘贴框底部安全区，与下边框留有 8dp 边距；
  - 无论文本多长，滑块在顶部时必定在最上端，滑块在底部时必定在最下端。

#### 要求 5：无需拖拽功能（穿透点击）
- 外层包裹 `IgnorePointer`，所有触摸、滑动、点击事件 100% 穿透给底层的 `TextField`，绝无手势抢占和误触问题。

---

## 三、文件修改清单

| 序号 | 文件路径 | 修改说明 |
|:---|:---|:---|
| 1 | `lib/pages/parse_page.dart` | 重构输入框外层结构，增加滚动监听、动态渐隐定时器、数学行程计算与纯指示滑块 |
| 2 | `pubspec.yaml` | 版本号升级为 `1.0.0+120` |
| 3 | `lib/app_info.dart` | 版本号升级为 `1.0.0+120` |
| 4 | `README.md` / `GEMINI.md` / `CLAUDE.md` | 同步更新版本号 `1.0.0+120` |

---

## 四、验证计划

1. **静态代码分析与单元测试**：
   - 运行 `flutter analyze` 确保 0 errors / 0 warnings；
   - 运行 `flutter test` 确保既有 63 个测试全部通过。
2. **模拟器端到端验证**：
   - 构建 `flutter build apk --debug` 并安装到模拟器；
   - 粘贴短文本：无滚动条，界面清爽；
   - 粘贴中长文本（如 10 行测试文本）：滑动时滑块平滑淡入，停止滑动 1.2 秒后平滑淡出；
   - 验证行程与边框：
     - 滑动到最顶部，截图检查滑块上边缘，确认不遮挡上边框与圆角；
     - 滑动到最底部，截图检查滑块下边缘，确认滑块准确停在输入框底部内侧；
     - 检查右侧边缘，确认与右边框线有清晰间距。

