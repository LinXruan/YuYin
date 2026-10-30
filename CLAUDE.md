# 项目开发守则 (Flutter Android)

## 1. 技术栈与目标平台
- **框架与语言**：Flutter 3.47.6 / Dart 3.13.5
- **目标平台**：仅开发 Android 端（忽略 Chrome/Web 及 Windows 桌面端的所有警告与配置）。

## 2. 常用命令与验证流程
每次修改完 Dart 代码后，请优先运行轻量级的静态检查，不要动辄跑完整的 APK 构建：
- **拉取依赖**：`flutter pub get`
- **代码静态检查（必跑）**：`flutter analyze`（改完代码后先用它检查语法错误，速度最快）
- **运行测试**：`flutter test`
- **构建测试包**：`flutter build apk --debug`
- **视觉验证脚本**：`D:\Install\anaconda3\envs\deepseek\python.exe tool\verify_launch_match.py`

## 3. 本地环境避坑指南（重要）
在终端执行命令时，必须严格遵守以下本地环境限制：
- **PowerShell**：已经升级到7.6.9版本了，默认使用PowerShell 7.6.9
- **Python 调用规范**：所有 Python 命令默认使用 conda 的 `deepseek` 环境，请使用完整路径 `D:\Install\anaconda3\envs\deepseek\python.exe`，或在单条命令中使用 `conda run -n deepseek python ...`。**严禁使用 `python3`**（会误调 MSYS2 环境导致缺包报错）；PATH 上的 `python` 指向 base 环境，也不要直接使用。VSCode 的默认解释器已通过
- **ADB 调用**：`platform-tools` 已加入当前用户的 PATH，新开的终端可直接运行 `adb`。若当前会话仍找不到 `adb`（PATH 未刷新），使用完整路径 `%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe`。运行 `tool\verify_launch_match.py` 时通常无需再传 `--adb`。
- **模拟器与内存保护**：可用模拟器 AVD 名称为 `Medium_Phone_API_37.0`。由于物理内存为 16GB 且 Gradle 分配了 `-Xmx8G`，在执行首次构建或重度 Gradle 编译时，**不要同时开启模拟器**，以免内存溢出。
- **JDK 版本**：Flutter 已固定使用 JDK 17（已执行 `flutter config --jdk-dir="C:\Program Files\Eclipse Adoptium\jdk-17.0.20.101-hotspot"`），`JAVA_HOME` 也指向该 JDK，不再使用 Android Studio 自带的 JBR 25。若出现 Java 版本问题，先运行 `flutter doctor -v` 确认 "Java binary at" 是否为 JDK 17。

## 4. Dart / Flutter 编码规范
- **极简原则**：我是编程新手，请使用最直观、标准的 Flutter 官方组件实现功能，除非我明确要求，否则不要引入复杂的第三方状态管理框架（优先使用基础的 `StatefulWidget` / `setState` 或项目中已有的方案）。
- **组件拆分**：保持单个 `.dart` 文件精简（尽量不超过 200 行），复杂的 UI 块请拆分为独立的 Widget 组件。
- **注释要求**：关键业务逻辑与 UI 结构请加上简明的中文注释。
