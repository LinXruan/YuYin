# PLAN_57: 检查重构架构与业务分层规范 (版本 1.5.5+170)

## 一、需求背景与目标

针对长期迭代形成的单体巨石文件（`douyin_sniffer.dart`、`js_script_builder.dart`、`media_item.dart`），进行清晰、高内聚、低耦合的分层重构。

明确软件业务本质划分为两大独立抓取域：
1. **主页链接批量抓取域（User Home）**：
   - 链接捕获接口（URL 解析与规范化）
   - 主页头像捕获接口
   - 主页昵称捕获接口
   - 作品数量 tag 捕获接口
   - 作品封面捕获接口
   - 作品名称捕获接口
2. **单链接解析具体资源下载域（Single Work）**：
   - 单作品名称抓取接口
   - 单作品封面抓取接口
   - 具体资源抓取接口（视频、图片、实况、音频）

重构原则：
- **不破坏现有行为**：保持 API 接口与外部调用兼容，平滑演进。
- **高内聚低耦合**：模型、服务、脚本均按两类领域垂直隔离。
- **全量测试守卫**：全量单元测试（236+ 项）和模拟器真实环境 100% 验证通过。

---

## 二、架构设计与目录分层

```text
lib/
├── models/
│   ├── common/                        # 作品类型枚举与基础数据
│   ├── single_work/                   # 单作品解析模型 (SingleWorkResult, MediaDownloadItem 等)
│   ├── user_home/                     # 主页批量模型 (UserHomeProfile, UserHomeResult 等)
│   └── media_item.dart                # 兼容导出入口 (保证既有导入零报错)
├── services/
│   ├── single_work/                   # 单作品解析服务域
│   │   ├── i_single_work_extractor.dart
│   │   └── single_work_extractor.dart
│   ├── user_home/                     # 主页批量抓取服务域
│   │   ├── i_user_home_extractor.dart
│   │   ├── user_profile_extractor.dart
│   │   └── user_home_batch_extractor.dart
│   └── douyin_sniffer.dart            # 外观门面 (Facade)，向下兼容代理
└── ...
```

---

## 三、任务分解与执行计划

1. [x] **版本号同步升级 (1.5.5+170)**：
   - 同步修改 `pubspec.yaml`, `lib/app_info.dart`, `GEMINI.md`, `CLAUDE.md`, `PLAN/PLAN_51~60/PLAN_57.md`。
2. [x] **阶段一：数据模型层按领域垂直拆解**：
   - 新建 `lib/models/common/work_type.dart`；
   - 新建 `lib/models/single_work/single_work_result.dart`、`lib/models/single_work/media_download_item.dart`；
   - 新建 `lib/models/user_home/user_home_profile.dart`、`lib/models/user_home/user_home_result.dart`；
   - 更新 `lib/models/media_item.dart` 提供透明 export 保证向后兼容；
   - 验证 `flutter analyze` 与全量测试。
3. [x] **阶段二：抽象两类抓取业务的契约接口 (Interfaces)**：
   - 定义 `ISingleWorkExtractor`（作品名称、封面、各资源直链解析）；
   - 定义 `IUserHomeExtractor`（主页链接、头像、昵称、作品tag、封面、作品名、批量作品列表）；
   - 确立清晰的数据契约与异常体系。
4. [x] **阶段三：服务层解耦落地与门面代理**：
   - 提取 `UserHomeExtractor` 实现 `IUserHomeExtractor`；
   - 提取 `SingleWorkExtractor` 实现 `ISingleWorkExtractor`；
   - `DouyinSniffer` 统一作为门面承接，内部调度分发并暴露领域 Extractor；
   - 解决同一 URL 连续请求时消息接收通道开启与 DOM 扫描时序优化。
5. [x] **阶段四：测试与回归验证**：
   - 编写重构专用单元测试 `test/plan_57_test.dart`（4/4 passed）；
   - 运行全量单测 `flutter test`（240/240 passed）；
   - 运行 `flutter analyze`（0 issues）。
6. [x] **阶段五：模拟器全流程实测**：
   - 部署 Debug APK 至带界面的模拟器（`emulator-5554`）；
   - 验证主页抓取域：3 位作者样本（宁采君、药厂人家、腿祖宗.Ann）头像与昵称比对 100% 完全匹配，全量主页作品（304条）、作品总数tag（302）、封面（304条）、标题（304条）100% 成功关联；
   - 验证单作品抓取域：实测视频作品标题、封面、11 档清晰度视频流解析与相册下载成功。
7. [x] **阶段六：Release 正式版编译与交付**：
   - 执行 `.\tool\build_release_apk.bat all` 编译发布包。
