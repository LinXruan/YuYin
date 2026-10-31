# PLAN_17：UI 与使用体验美化方案（版本 1.0.0+119）

## 一、需求背景与目标

在完成了自动识别登录/退出状态（PLAN_16）后，本项目在核心功能上已趋于成熟。用户提出了 5 项关键的 UI 美化与交互优化需求，进一步提升“余音”的视觉质感和操作舒适度：

1. **开屏动画图标一致性**：开屏动画图片由原先的方形/过大音符调整为与桌面软件图标完全一致的圆形图标，尺寸与视觉重心保持统一。
2. **链接输入框固定高度 + 纵向滚动条**：取消原本动态扩张行数的逻辑，改为固定高度（约 120dp）；文本超出时依然支持上下滑动浏览，右侧增加精致竖向滑动条（Scrollbar）。
3. **“粘贴”与“清空”按钮美化与右对齐**：将这两个纯文本按钮移至屏幕右侧，并升级为带有背景色块与图标的 Material 3 按钮（如 Tonal / Filled Button 带图标）。
4. **调试页一键清空日志**：在“设置 -> 调试”日志界面的 AppBar 中，在“复制日志”旁边新增“清空日志”按钮，便于调试时快速清理冗余信息。
5. **关于页新增反馈 QQ 群**：在“制作人”下方新增“反馈交流群”（QQ群：`1132880576`），保持与开源地址一致的布局，右侧附带一键复制群号按钮。
6. **版本号升级**：全项目版本号从 `1.0.0+118` 升级为 `1.0.0+119`。

---

## 二、详细修改方案与设计

### 1. 开屏动画图标一致性（Android Launch Logo / Splash Screen）
- **问题分析**：
  - 目前 `tool/generate_app_icon.py` 中，启动页 logo（`launch_logo.png`）的音符字号比例为 `font_ratio=0.62`，画布为 120dp；而桌面自适应图标（`ic_launcher_foreground.png`）音符字号比例为 `0.50`，导致开屏音符明显偏大（大约偏大 24%）。
  - 在 Android 12+（API 31+）上，`values-v31/styles.xml` 原配置了 `<item name="android:windowSplashScreenAnimatedIcon">@drawable/launch_logo</item>`。由于 `launch_logo` 是普通静态 PNG，在部分厂商系统（如澎湃OS、ColorOS、OriginOS）上未被系统自适应裁剪为圆底，或被包装在默认方形卡片中。
- **解决方案**：
  1. **脚本重构（`tool/generate_app_icon.py`）**：
     - 将 `launch_logo` 的音符渲染比例调整为 `0.50`，竖向微调位移保持 `y_shift_ratio=0.04`，与桌面自适应图标的前景比例严格一致。
     - 尺寸调整为与标准图标一致的圆底图标，确保在低版本 Android（`< API 31` 走 `launch_background.xml`）居中显示时为精致圆底 + 居中音符。
     - 重新执行图标生成脚本更新 `res/drawable-*/launch_logo.png` 与 `res/mipmap-*/`。
  2. **Android 12+ 适配（`res/values-v31/styles.xml` 与 `values-night-v31/styles.xml`）**：
     - 将 `windowSplashScreenAnimatedIcon` 指定为 `@mipmap/ic_launcher`。
     - Android 12+ 的 Splash 规范推荐使用自适应图标（Adaptive Icon XML），系统在启动时会自动提取粉色圆底背景与居中音符前景，并调用官方圆形遮罩与进退场动画，实现与桌面图标 100% 像素级一致。

---

### 2. 链接输入框固定高度 + 纵向滑动条
- **文件**：`lib/pages/parse_page.dart`
- **方案**：
  1. 在 `_ParsePageState` 中添加独立的 `final ScrollController _inputScrollController = ScrollController();`，并在 `dispose()` 中释放。
  2. 将原有的 `TextField`（`minLines: 3, maxLines: 5` 自动拉伸方案）改为固定高度容器：
     ```dart
     SizedBox(
       height: 120, // 固定高度，可舒适容纳约 4-5 行文本
       child: Scrollbar(
         controller: _inputScrollController,
         thumbVisibility: true, // 始终或在滚动时展示滚动条
         radius: const Radius.circular(4),
         thickness: 4,
         child: TextField(
           controller: _inputController,
           scrollController: _inputScrollController,
           maxLines: null,
           expands: true,
           textAlignVertical: TextAlignVertical.top,
           decoration: const InputDecoration(
             labelText: '抖音分享口令 / 链接',
             hintText: '粘贴分享口令或链接，例如 https://v.douyin.com/xxxx/',
             border: OutlineInputBorder(),
             alignLabelWithHint: true,
           ),
         ),
       ),
     )
     ```
  3. 输入框大小不再随文字多少忽大忽小，内容超出时可平滑上下滑动，右侧显示细长、贴合整体色调的半透明小滑块。

---

### 3. “粘贴”与“清空”按钮右对齐并升级外观
- **文件**：`lib/pages/parse_page.dart`
- **方案**：
  1. 将原本位于左侧的两个无底色 `TextButton` 移至右侧：`Row(mainAxisAlignment: MainAxisAlignment.end, children: [...])`。
  2. 采用 Material 3 `FilledButton.tonalIcon`，增加精致背景色块与语义化图标：
     - **“粘贴”**：
       - 图标：`Icons.paste_rounded`
       - 样式：`FilledButton.tonalIcon`（背景为优雅的浅调色块）
       - 点击：调用 `_pasteFromClipboard`
     - **“清空”**：
       - 图标：`Icons.delete_outline_rounded`
       - 样式：`FilledButton.tonalIcon` 或 `OutlinedButton.icon`，具备明确的按钮轮廓和色块
       - 点击：清空输入框文本
  3. 整体视觉更加立体清晰，防止误触，符合单手操作习惯。

---

### 4. 调试页一键清空日志按钮
- **文件**：`lib/pages/debug_page.dart`
- **方案**：
  1. 在 AppBar 的 `actions` 中，在“复制日志”前并排新增“清空日志”按钮：
     ```dart
     actions: [
       Builder(
         builder: (buttonContext) => IconButton(
           tooltip: '清空日志',
           onPressed: () => _clearLogs(buttonContext),
           icon: const Icon(Icons.delete_sweep_outlined),
         ),
       ),
       Builder(
         builder: (buttonContext) => IconButton(
           tooltip: '复制日志',
           onPressed: () => _copyLogs(buttonContext),
           icon: const Icon(Icons.copy),
         ),
       ),
     ]
     ```
  2. 实现 `_clearLogs` 逻辑：
     - 若 `logs.value.isEmpty`，提示“日志已为空”；
     - 若有内容，调用 `logs.clear()`，并弹出 SnackBar 提示“已清空日志”。

---

### 5. 关于页新增“反馈交流Q群”
- **文件**：`lib/app_info.dart`、`lib/pages/about_page.dart`
- **方案**：
  1. `lib/app_info.dart` 中新增常量：
     ```dart
     const String appFeedbackGroup = '1132880576';
     ```
  2. `lib/pages/about_page.dart` 中，在“制作人”列表项下方增加分割线并新增一行 `ListTile`：
     - `leading`: `Icon(Icons.group_outlined)`
     - `title`: `Text('反馈交流Q群')`
     - `subtitle`: `SelectableText(appFeedbackGroup)`
     - `trailing`: 复制按钮 `IconButton(tooltip: '复制群号', icon: Icon(Icons.copy, size: 20), onPressed: ...)`
     - 点击复制按钮触发 `_copyFeedbackGroup`，将群号复制到剪贴板并提示“已复制反馈群号”。

---

### 6. 版本号与配置同步
- 将版本号更新为 `1.0.0+119`：
  - `pubspec.yaml`: `version: 1.0.0+119`
  - `lib/app_info.dart`: `appVersion = '1.0.0+119'`
  - 维护说明文档：`README.md`、`GEMINI.md`、`CLAUDE.md`

---

## 三、文件变更清单与执行步骤

| 步骤 | 操作类型 | 文件路径 | 变更说明 |
|:---|:---|:---|:---|
| 1 | 修改 & 运行 | `tool/generate_app_icon.py` | 调整 `launch_logo` 音符比例为 `0.50` 与圆底生成逻辑，运行脚本重新生成图片资源 |
| 2 | 修改 | `android/app/src/main/res/values-v31/styles.xml`<br>`android/app/src/main/res/values-night-v31/styles.xml` | 将 Android 12+ Splash 图标更新为官方自适应圆形图标 `@mipmap/ic_launcher` |
| 3 | 修改 | `lib/pages/parse_page.dart` | 固定高度 120dp、集成 `_inputScrollController` 与 `Scrollbar`；按钮右对齐并升级为有底色+图标的按钮 |
| 4 | 修改 | `lib/pages/debug_page.dart` | AppBar 新增清空日志按钮 `delete_sweep_outlined` 与 `_clearLogs` 交互 |
| 5 | 修改 | `lib/app_info.dart`<br>`lib/pages/about_page.dart` | 新增 `appFeedbackGroup` 常量与列表项，升级版本号至 `1.0.0+119` |
| 6 | 修改 | `pubspec.yaml`<br>`README.md`<br>`GEMINI.md`<br>`CLAUDE.md` | 同步版本号 `1.0.0+119` |
| 7 | 验证 | 测试与构建 | 执行 `flutter analyze`、`flutter test`、构建 debug apk 并安装至模拟器验证 |

---

## 四、验证计划

1. **静态代码分析与单元测试**：
   - 运行 `flutter analyze` 确保 0 warnings/errors。
   - 运行 `flutter test` 确保既有 63 个测试全部通过。
2. **模拟器 UI 自动化与真机安装验证**：
   - 构建 `flutter build apk --debug` 并安装到模拟器 `emulator-5554`。
   - **冷启动开屏**：重启应用查看开屏动画，确认图标为圆形，音符尺寸与位置同应用图标严格统一。
   - **解析页输入框**：输入长文本口令，观察固定 120dp 高度、右侧垂直滑动条展示与上下顺畅滑动。
   - **操作按钮**：查看“粘贴”与“清空”是否位于右侧，是否展示背景色块和对应图标，点击清空与粘贴是否灵敏有效。
   - **调试页日志清空**：在设置页进入调试，点击右上角清空按钮，验证日志面板即时变空并展示 SnackBar。
   - **关于页反馈群号**：进入关于页，验证制作人下方新增的反馈群条目，点击右侧复制按钮验证剪贴板是否正确复制 `1132880576`。

