# PLAN_16：自动识别 WebView 抖音登录状态（118）

## 背景

在 115、116、117 迭代中逐步完成 WebView 登录与登出的精准双向感知。
118 版本针对用户提出的 3 项精简与微调需求进行落地：
1. **彻底移除用户昵称抓取与展示**：无需读取、记录、展示个人昵称，保持极致隐私与简洁；
2. **优化“我的主页”横幅 Tips**：
   - 顶部加粗提示：`已成功登录`；
   - 细字提示：`点击右上角小头像，即可退出登录`（正在自动返回时提示 `正在自动返回 (1.5s)...`）；
3. **应用图标音符位置微调**：
   - 在 `tool/generate_app_icon.py` 中将 Material Icons `music_note` 略微往正下方平移（4% 比例），弥补长音符竖杆导致的视觉重心偏上问题，并重新生成全部分辨率图标。

## 涉及文件

- `tool/generate_app_icon.py` (微调音符 Y 轴坐标，重绘全套启动图标与 Splash Logo)
- `lib/services/login_detector_script.dart` (剔除昵称抓取逻辑，保留高可靠官方凭证校验与登出感知)
- `lib/pages/login_webview_page.dart` (精简 Tips，移除昵称展示，文案清晰明确)
- `lib/pages/app_shell.dart` (日志移除昵称展示)
- `lib/app_info.dart` (版本升级至 118)
- `pubspec.yaml` (版本升级至 118)
- `README.md` / `CLAUDE.md` / `GEMINI.md` (同步更新至 118)
- `test/login_detector_test.dart` (同步测试用例)
- `PLAN/PLAN_16.md` (归档)

## 验证结果

- `node --check`：JS 语法 100% 合法；
- `flutter analyze`：No issues found!
- `flutter test`：测试全部通过；
- `python tool/generate_app_icon.py`：全套图标重新渲染完毕；
- `flutter build apk --debug`：构建成功；
- 模拟器部署：覆盖安装并启动验证。
