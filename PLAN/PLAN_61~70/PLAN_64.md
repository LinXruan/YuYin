# PLAN_64：文件级重构与深度分层（版本 1.5.5+178）

## 一、目标与边界

### 1.1 目标

1. **消灭大文件**：所有超过 400 行的 Dart 文件必须拆分，目标单文件 **≤ 250 行**，上限 400 行。
2. **深度分层**：不是把文件摊在同一个目录里，而是按「分层 → 领域 → 子领域 → 角色」四级落位，每个目录只装同一职责的东西。
3. **面向对象**：把过程式堆砌的状态与逻辑收敛到领域对象、流程混入、协议处理器、纯解析器中；页面只做渲染与编排。
4. **可维护性**：改一个功能只需要动一个目录；新增功能有明确的落位规则，不需要临时决定放哪。

### 1.2 边界（本次不做）

- **不做 Debug 联调**，不需要模拟器、不需要验收业务行为。
- **不做逻辑修改**：不修 bug、不改时序、不改阈值、不改文案、不改日志文本。
- **不改公开 API 语义**：类名、构造参数、静态方法签名保持不变（文件路径允许变动，import 由 analyzer 兜底批量修正）。
- 不改 Android 原生、构建脚本、资源文件。

### 1.3 唯一硬约束：逻辑等价

拆分只能做「剪切 + 重命名 + 组合 + 移动」，不允许借机重写算法。判定标准：

- `flutter analyze` 0 issues；
- `flutter test` 319/319 全绿（当前基线）；
- `kDouyinSniffJs` 拼接结果与拆分前**逐字节相同**；
- 公开符号与调用点语义不变，diff 中不出现业务表达式改写。

---

## 二、分层与命名规范（本次重构的落位依据）

### 2.1 目录深度约定

统一采用四级路径，**最深 5 段（不含 `lib`），不再更深**：

```
lib / <分层> / <领域> / <子领域> / <角色> / <文件>.dart
```

| 层级 | 取值 | 说明 |
| --- | --- | --- |
| 分层 | `models` `services` `pages` `widgets` `utils` | 只允许这五种，不新增根目录 |
| 领域 | `sniffer` `share` `bridge` `script` `update` `parse` `history` `save_page` … | 一个业务域一个目录 |
| 子领域 | `single` `home` `multi` `profile` `fallback` `top` `middle` `bottom` … | 领域内的分支 |
| 角色 | `page` `flow` `widget` `handler` `parser` `model` `session` `debug` `memory` … | 单一职责单元 |

**建目录的硬规则**：

1. 同一目录下 **2~8 个文件**。少于 2 个不建目录（直接用角色后缀命名平铺）。
2. 超过 8 个必须再分一层子目录。
3. 目录名一律小写蛇形，与文件角色一致。
4. 禁止 `misc`、`common`、`utils` 这类万能垃圾桶目录；`common` 只允许放跨子领域共用的**同一角色**文件。

### 2.2 角色词表（文件名后缀即职责）

| 后缀 | 职责 | 允许包含 | 禁止包含 |
| --- | --- | --- | --- |
| `_page.dart` | 页面骨架 | Widget、State 字段、`build` | 业务流程、解析算法 |
| `_flow.dart` | 流程混入（mixin） | 用户操作与异步编排 | 新建字段、`initState` |
| `_controller.dart` | 可实例化控制器 | 状态机、定时器、回调 | UI 依赖 |
| `_handler.dart` | 协议/端点处理器 | 单端点请求→响应 | 其他端点逻辑 |
| `_parser.dart` | 纯解析函数 | `static` 纯函数 | 网络、UI、全局状态 |
| `_picker.dart` | 选择/挑选策略 | 纯函数 | 副作用 |
| `_builder.dart` | 构造器 | 组装对象/字符串 | 业务判断 |
| `_model.dart` | 数据模型 | 不可变数据、`fromJson` | 业务流程 |
| `_session.dart` | 任务态 | ID、定时器、预算 | UI |
| `_tile.dart` `_card.dart` `_bar.dart` `_banner.dart` | 原子组件 | 单条目渲染 | 列表编排 |
| `_snapshot.dart` | 调试快照 | 只读序列化 | 状态修改 |
| `_memory.dart` | 记忆写入 | Store 调用 | UI |

### 2.3 三种拆分手法

| 手法 | 适用 | 等价性 | 说明 |
| --- | --- | --- | --- |
| A. 纯函数外移 | 无状态工具、解析器 | 极高 | 新建 `*_parser.dart`/`*_picker.dart`，原处保留一行转发 |
| B. `part` + `mixin` | 巨型 State / 巨型 Service | 高 | 入口文件 `part` 子目录文件；mixin `on` 原类，可访问同类私有成员 |
| C. 协作者注入 | 有明确依赖边界的模块 | 中高 | 抽出 `XxxHandler`，由原类持有，原方法改为一行委托 |

> **入口文件保留原路径，作为 library 根**：测试全部冻结且直接 `import 'package:yuyin/pages/parse_page.dart'` 等路径（共 55 条），移动会破坏测试。因此入口文件原位不动，只负责「字段 + 生命周期 + `part` 声明 + 门面方法」，拆出的流程与组件全部下沉到子目录。`part` 属于同一 library，`StatusCard` 等符号仍可被外部 import 直接使用。

---

## 三、扫描结果

### 3.1 超过 400 行的文件（必须拆分，11 个，合计 10,323 行）

| # | 现文件 | 行数 | 主要问题 |
| --- | --- | --- | --- |
| 1 | `services/agent_automation_server.dart` | 1518 | 32 个 `_handleXxx` 平铺，路由与业务混在一起 |
| 2 | `services/douyin_sniffer.dart` | 1471 | 生命周期、导航、消息解析、兜底链路、主页流程全在一个类 |
| 3 | `pages/parse_page.dart` | 1365 | 单作品/主页/多作品三条流程 + 进度 + 4 个内嵌 Widget |
| 4 | `services/js_script_builder.dart` | 1191 | 一段 1100 行 JS 字符串，无任何分层 |
| 5 | `pages/history_page.dart` | 886 | 搜索、多选、删除、卡片、空态、缩略图混在一个 State |
| 6 | `services/douyin_share_api.dart` | 756 | HTTP 客户端 + Cookie + HTML 解析 + 媒体挑选 |
| 7 | `widgets/save_page/middle_multi_work_sheet.dart` | 592 | 作品选择、分类筛选、画质、调试快照、Tile 全在一个 State |
| 8 | `widgets/save_page/top_multi_home_sheet.dart` | 560 | 同上（作者层） |
| 9 | `widgets/save_page/bottom_media_sheet.dart` | 530 | 资源选择、音频播放、预览弹窗、Tile |
| 10 | `widgets/update_dialog.dart` | 520 | 弹窗 + 更新日志滚动 + 自研 Markdown 渲染 |
| 11 | `pages/app_shell.dart` | 440 | 全局初始化、登录、自动检查更新、底部导航、更新进度条 |

### 3.2 第二批（250~400 行，越细越好阶段处理）

| 文件 | 行数 | 目标落位 |
| --- | --- | --- |
| `services/update_checker.dart` | 410 | `services/update/{client,model,version,parser,error}` |
| `utils/url_parser.dart` | 399 | `utils/url/{detect,classify,normalize}` |
| `utils/selection_mode_store.dart` | 352 | `utils/selection/{store,scope,migrate}` |
| `utils/app_update_store.dart` | 346 | `utils/update/{store,state,progress}` |
| `utils/save_location_store.dart` | 342 | `utils/savelocation/{store,query}` |
| `services/login_detector_script.dart` | 334 | `services/script/login/chunk/` |
| `widgets/save_location_dialog.dart` | 328 | `widgets/savelocation/{dialog,list,action}` |
| `widgets/save_page/bottom_media_widgets.dart` | 313 | 拆入 `widgets/save_page/bottom/widget/` |
| `utils/history_thumbnail_cache.dart` | 301 | `utils/thumbnail/{cache,index,download}` |
| `utils/download_settings_store.dart` | 298 | `utils/downloadsettings/{store,scope}` |
| `widgets/save_page/save_page_common.dart` | 294 | `widgets/save_page/common/{tile,chip,header,footer}` |

### 3.3 目标目录树（重构后）

```
lib/
├── models/
│   ├── common/                      # MediaType、保存目标、记忆作用域
│   ├── single_work/                 # 单作品模型
│   ├── user_home/                   # 主页作者与全量作品
│   ├── save_page/
│   │   ├── tree/                    # 选择树状态、作者作品选择
│   │   ├── work/                    # SaveWorkItem、WorkKind、保存结果
│   │   └── media/                   # 多作品提取结果、资源选择
│   └── history/                     # 历史记录类型、可用性
│
├── services/
│   ├── sniffer/
│   │   ├── facade/                  # DouyinSniffer 本体
│   │   ├── session/                 # 任务态、超时预算
│   │   ├── channel/                 # JS 通道消息解析
│   │   ├── webview/                 # 控制器构建、UA 管理
│   │   └── flow/
│   │       ├── single/              # 单作品抓取、消息收尾、分享页兜底
│   │       ├── common/              # 导航决策、资源错误
│   │       └── home/                # 主页作品、作者资料
│   ├── share/
│   │   ├── client/                  # Dio 请求与 Cookie 重试
│   │   ├── cookie/                  # Set-Cookie 合并
│   │   ├── parser/
│   │   │   ├── html/                # RouterData 抽取
│   │   │   ├── item/                # 作品条目、画质档位
│   │   │   └── media/               # 封面/图片/音频挑选
│   │   └── model/                   # 异常与结果模型
│   ├── script/
│   │   ├── douyin/chunk/            # 注入脚本分片
│   │   └── login/chunk/             # 登录探针分片
│   ├── bridge/
│   │   ├── server/                  # 服务器生命周期、路由表
│   │   ├── handler/
│   │   │   ├── status/ parse/ save/ download/
│   │   │   ├── history/ log/ media/ verify/ system/
│   │   ├── protocol/                # 上下文、请求、响应、序列化
│   │   └── support/                 # 端点共用的小工具
│   ├── update/
│   │   ├── client/ model/ version/ parser/ error/
│   ├── single_work/ user_home/ multi_work/   # 既有提取器
│   └── batch_work/ history/          # 既有批量保存
│
├── pages/
│   ├── parse/
│   │   ├── page/
│   │   ├── flow/{single,home,multi,common}/
│   │   ├── widget/{status,banner,input}/
│   │   └── support/                 # 委托、文案标签
│   ├── history/
│   │   ├── page/
│   │   ├── flow/{search,selection,action}/
│   │   └── widget/{card,filter,banner,empty}/
│   ├── shell/
│   │   ├── page/
│   │   ├── bootstrap/
│   │   └── widget/
│   └── （settings/about/login/debug 保持原位）
│
└── widgets/
    ├── save_page/
    │   ├── top/{page,flow,widget,debug,memory}/
    │   ├── middle/{page,flow,widget,debug,memory}/
    │   ├── bottom/{page,flow,widget,debug,memory}/
    │   └── common/
    ├── update/{dialog,notes,markdown}/
    └── （history/image_preview/log_panel 等保持原位）
```

---

## 四、逐文件拆分设计（含最终路径）

### 4.1 `agent_automation_server.dart` → `services/bridge/`

入口下沉到 `server/`，只做生命周期与路由分发，业务全部交给 handler。

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `services/bridge/server/agent_automation_server.dart` | HttpServer 启停、依赖持有 | 180 |
| `services/bridge/server/agent_router.dart` | 路径→handler 注册与匹配 | 80 |
| `services/bridge/handler/i_agent_handler.dart` | `IAgentHandler` 契约 | 30 |
| `services/bridge/protocol/bridge_context.dart` | `AgentBridgeContext` 依赖包 | 80 |
| `services/bridge/protocol/bridge_request.dart` | JSON body / query 读取 | 70 |
| `services/bridge/protocol/bridge_response.dart` | JSON 响应与错误码 | 60 |
| `services/bridge/protocol/bridge_serializers.dart` | 条目/保存结果序列化、画质枚举解析 | 120 |
| `services/bridge/support/base_name_utils.dart` | 端点共用的小工具 | 60 |
| `services/bridge/handler/status/status_handler.dart` | `/api/status` | 90 |
| `services/bridge/handler/parse/parse_handler.dart` | `/api/parse` | 200 |
| `services/bridge/handler/parse/parse_works_handler.dart` | `/api/parse-works` | 130 |
| `services/bridge/handler/parse/parse_profile_handler.dart` | `/api/parse-profile` | 110 |
| `services/bridge/handler/save/save_works_handler.dart` | `/api/save/works` | 110 |
| `services/bridge/handler/save/save_home_handler.dart` | `/api/save/home` | 140 |
| `services/bridge/handler/download/download_handler.dart` | `/api/download` | 150 |
| `services/bridge/handler/history/history_query_handler.dart` | `/api/history` | 80 |
| `services/bridge/handler/history/history_scan_handler.dart` | `/api/history/scan` | 90 |
| `services/bridge/handler/history/history_open_handler.dart` | `/api/history/open` | 70 |
| `services/bridge/handler/history/history_clear_handler.dart` | `/api/history/clear` | 40 |
| `services/bridge/handler/log/log_handler.dart` | 日志读取/清空 | 80 |
| `services/bridge/handler/media/display_mode_handler.dart` | 显示模式 | 50 |
| `services/bridge/handler/media/thumbnail_handler.dart` | 缩略图状态/清空/预热 | 110 |
| `services/bridge/handler/media/quality_handler.dart` | 画质设置 | 50 |
| `services/bridge/handler/verify/verify_covers_handler.dart` | 封面校验 | 110 |
| `services/bridge/handler/verify/verify_titles_handler.dart` | 标题校验 | 110 |
| `services/bridge/handler/verify/verify_profile_handler.dart` | 头像昵称校验 | 100 |
| `services/bridge/handler/system/eval_handler.dart` | `/api/eval` | 70 |
| `services/bridge/handler/system/cancel_handler.dart` | `/api/cancel` | 40 |
| `services/bridge/handler/system/mock_login_handler.dart` | `/api/mock-login` | 40 |

### 4.2 `douyin_sniffer.dart` → `services/sniffer/`

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `services/sniffer/facade/douyin_sniffer.dart` | 字段、构造、生命周期、注入、三提取器委托 | 280 |
| `services/sniffer/session/sniffer_task_state.dart` | 任务 ID、起始时间、各定时器 | 110 |
| `services/sniffer/session/sniffer_timeout_budget.dart` | 超时常量与纯计算函数 | 70 |
| `services/sniffer/channel/sniffer_channel_parser.dart` | 登录态/条目/JS 结果解析 | 110 |
| `services/sniffer/webview/sniffer_webview_builder.dart` | WebViewController 构建与回调挂载 | 100 |
| `services/sniffer/webview/sniffer_user_agent.dart` | 桌面/移动 UA 切换与恢复 | 70 |
| `services/sniffer/flow/single/single_sniff_flow.dart` | `sniffVideoUrl`/`sniffWork` | 220 |
| `services/sniffer/flow/single/sniff_message_flow.dart` | JS 消息、登录态、带结果收尾 | 220 |
| `services/sniffer/flow/single/sniff_share_fallback_flow.dart` | Dio 分享页兜底 | 150 |
| `services/sniffer/flow/single/sniff_webview_fallback_flow.dart` | WebView 分享页兜底、图片宽限 | 160 |
| `services/sniffer/flow/common/sniff_navigation_flow.dart` | 导航决策、资源错误、验证码 | 180 |
| `services/sniffer/flow/home/home_sniff_flow.dart` | 主页作品抓取与收尾 | 200 |
| `services/sniffer/flow/home/profile_sniff_flow.dart` | 作者资料抓取与收尾 | 120 |

手法：B（`part` + `mixin on DouyinSniffer`）。字段与 `initState` 全部留在门面文件。

### 4.3 `parse_page.dart` → `pages/parse/`

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `pages/parse/page/parse_page.dart` | Widget、State 字段、生命周期、`build` | 250 |
| `pages/parse/flow/single/single_parse_flow.dart` | `_startParse`、`_chooseItems` | 220 |
| `pages/parse/flow/home/home_parse_flow.dart` | 主页多链接并行解析 | 180 |
| `pages/parse/flow/home/home_author_open_flow.dart` | 打开作者、补抓作品 | 120 |
| `pages/parse/flow/multi/multi_parse_flow.dart` | 多作品批量解析 | 140 |
| `pages/parse/flow/multi/multi_work_open_flow.dart` | 打开单作品详情 | 120 |
| `pages/parse/flow/common/parse_progress_flow.dart` | 批量/单条进度与回调 | 150 |
| `pages/parse/flow/common/parse_input_flow.dart` | 粘贴、输入滚动、取消 | 120 |
| `pages/parse/widget/status/status_card.dart` | `StatusCard`（公开，测试依赖） | 120 |
| `pages/parse/widget/banner/login_prompt_banner.dart` | 登录提示横幅 | 150 |
| `pages/parse/widget/input/parse_input_bar.dart` | 输入框与按钮区 | 140 |
| `pages/parse/support/home_works_delegate.dart` | `HomeWorksDelegate` | 40 |
| `pages/parse/support/parse_labels.dart` | 媒体摘要、画质标签、友好错误 | 70 |

### 4.4 `js_script_builder.dart` → `services/script/douyin/`

字符串按 JS 函数边界切片，入口只做顺序拼接。**拆分前导出原始字符串 SHA-1 基线，拆分后逐字节比对。**

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `services/script/douyin/douyin_sniff_script.dart` | `const kDouyinSniffJs = ...` 拼装 | 70 |
| `services/script/douyin/chunk/js_state_header.dart` | 状态对象、`log`、起始时间 | 70 |
| `services/script/douyin/chunk/js_login_probe.dart` | 登录态上报与探测 | 130 |
| `services/script/douyin/chunk/js_media_extract.dart` | URL 清洗、码率挑选、视频/图片/音频收集 | 240 |
| `services/script/douyin/chunk/js_network_hook.dart` | 网络拦截、awemeId 提取、结果上报 | 200 |
| `services/script/douyin/chunk/js_scan_engine.dart` | 播放器/树/节奏/RSC 扫描 | 220 |
| `services/script/douyin/chunk/js_home_collect.dart` | 滚动、作品追加、进度、完成判定 | 260 |
| `services/script/douyin/chunk/js_profile_extract.dart` | 头像昵称、资料 JSON、DOM 扫描 | 160 |
| `services/script/douyin/chunk/js_title_cover.dart` | 标题、封面、作者头像挑选 | 120 |
| `services/script/douyin/chunk/js_reset.dart` | 重置函数与 IIFE 收尾 | 50 |

### 4.5 `history_page.dart` → `pages/history/`

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `pages/history/page/history_page.dart` | Widget、State 字段、监听、骨架 | 230 |
| `pages/history/flow/search/history_search_flow.dart` | 搜索防抖、清空、筛选已保存 | 100 |
| `pages/history/flow/selection/history_selection_flow.dart` | 多选、全选、删除确认 | 170 |
| `pages/history/flow/action/history_action_flow.dart` | 复制链接、打开、定位 | 150 |
| `pages/history/widget/card/history_card.dart` | 单条卡片 | 160 |
| `pages/history/widget/card/history_card_thumbnail.dart` | 缩略图异步加载 | 90 |
| `pages/history/widget/filter/history_filter_button.dart` | 筛选胶囊 | 90 |
| `pages/history/widget/banner/history_prompt_banner.dart` | 提示栏 | 90 |
| `pages/history/widget/empty/history_empty_state.dart` | 空态 | 60 |

### 4.6 `douyin_share_api.dart` → `services/share/`

保留 `DouyinShareApi` 的全部 static 方法（一行转发），测试直接调用不变。

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `services/share/client/douyin_share_api.dart` | 请求、Cookie 重试、取消、static 转发 | 180 |
| `services/share/model/share_models.dart` | 异常与结果模型 | 60 |
| `services/share/cookie/share_cookie.dart` | Set-Cookie 解析与合并 | 60 |
| `services/share/parser/html/share_router_data.dart` | RouterData 抽取 | 90 |
| `services/share/parser/html/share_html_parser.dart` | HTML→结果组装 | 130 |
| `services/share/parser/item/share_item_parser.dart` | 条目解析、画质档位 | 180 |
| `services/share/parser/media/share_media_picker.dart` | 视频/封面/图片/音频挑选 | 180 |

### 4.7 三个保存页 → `widgets/save_page/{top,middle,bottom}/`

**顶层（560）**

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `widgets/save_page/top/page/top_multi_home_sheet.dart` | Widget、State 字段、`show`、骨架 | 190 |
| `widgets/save_page/top/flow/top_author_selection_flow.dart` | 作者/全选/状态刷新 | 150 |
| `widgets/save_page/top/flow/top_quality_flow.dart` | 画质聚合与切换 | 90 |
| `widgets/save_page/top/widget/top_author_tile.dart` | 作者行 + 头像 | 130 |
| `widgets/save_page/top/widget/top_sheet_footer.dart` | 底部保存栏 | 70 |
| `widgets/save_page/top/debug/top_debug_snapshot.dart` | 调试快照 | 90 |
| `widgets/save_page/top/memory/top_selection_memory.dart` | 记忆写入 | 70 |

**中层（592）**

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `widgets/save_page/middle/page/middle_multi_work_sheet.dart` | Widget、State 字段、`show`、骨架 | 190 |
| `widgets/save_page/middle/flow/middle_work_selection_flow.dart` | 作品勾选与递归 | 150 |
| `widgets/save_page/middle/flow/middle_category_flow.dart` | 分类索引与分类全选 | 110 |
| `widgets/save_page/middle/flow/middle_quality_flow.dart` | 画质聚合与切换 | 90 |
| `widgets/save_page/middle/widget/middle_work_tile.dart` | 作品行 + 封面 | 130 |
| `widgets/save_page/middle/widget/middle_sheet_footer.dart` | 底部保存栏 | 70 |
| `widgets/save_page/middle/debug/middle_debug_snapshot.dart` | 调试快照 | 70 |
| `widgets/save_page/middle/memory/middle_selection_memory.dart` | 记忆写入 | 70 |

**底层（530）**

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `widgets/save_page/bottom/page/bottom_media_sheet.dart` | Widget、State 字段、`show`、骨架 | 190 |
| `widgets/save_page/bottom/flow/bottom_media_selection_flow.dart` | 选中切换、分类、确认 | 130 |
| `widgets/save_page/bottom/flow/bottom_audio_flow.dart` | 音频播放与关闭 | 100 |
| `widgets/save_page/bottom/widget/bottom_media_tile.dart` | 资源格 + 播放按钮 | 140 |
| `widgets/save_page/bottom/widget/bottom_audio_bar.dart` | 音频播放条 | 90 |
| `widgets/save_page/bottom/widget/bottom_media_preview.dart` | 大图预览弹窗 | 80 |
| `widgets/save_page/bottom/debug/bottom_debug_snapshot.dart` | 调试快照 | 70 |
| `widgets/save_page/bottom/memory/bottom_selection_memory.dart` | 记忆写入 | 70 |

### 4.8 `update_dialog.dart` → `widgets/update/`

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `widgets/update/dialog/update_dialog.dart` | 主弹窗与操作按钮 | 160 |
| `widgets/update/notes/release_notes_box.dart` | 更新日志滚动盒 | 150 |
| `widgets/update/markdown/markdown_render_view.dart` | 块级渲染 | 200 |
| `widgets/update/markdown/markdown_inline_parser.dart` | 行内样式解析 | 90 |

### 4.9 `app_shell.dart` → `pages/shell/`

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `pages/shell/page/app_shell.dart` | 三 Tab 骨架、全局服务持有 | 200 |
| `pages/shell/bootstrap/shell_bootstrap_flow.dart` | 初始化、登录态、自动检查更新 | 150 |
| `pages/shell/widget/shell_tab_bar.dart` | 底部导航 | 90 |
| `pages/shell/widget/shell_update_banner.dart` | 更新进度条 | 90 |

### 4.10 `update_checker.dart` → `services/update/`

| 最终路径 | 内容 | 行数 |
| --- | --- | --- |
| `services/update/client/update_checker.dart` | 请求编排与结果模型 | 180 |
| `services/update/model/update_release_info.dart` | 版本信息与下载地址 | 80 |
| `services/update/version/update_version.dart` | 版本比较与清洗 | 70 |
| `services/update/parser/update_atom_parser.dart` | Atom/RSS 解析 | 120 |
| `services/update/parser/update_html_cleaner.dart` | HTML 正文清洗 | 80 |
| `services/update/error/update_error_text.dart` | Dio/未知错误文案 | 90 |

---

## 五、执行顺序（每阶段独立可回滚）

1. **基线固化**：记录 `kDouyinSniffJs` 的 SHA-1、11 个文件行数、319 条测试基线。
2. **叶子层（纯函数）**：`script` → `share` → `update`。每步后 analyze + 相关测试。
3. **服务层**：`bridge`（handler 化）→ `sniffer`（part + mixin）。
4. **页面层**：`parse` → `history` → `shell`。
5. **组件层**：保存页 top/middle/bottom → `update`。
6. **第二批（250~400 行）**：按 3.2 表继续拆，目标全库无文件超 400 行（理想 ≤250）。
7. **门禁**：新增 `test/plan_64_test.dart`（行数门禁 + 目录规范 + JS 校验），版本号改 `1.5.5+178`，analyze 0、test 全绿。

> 顺序理由：先做无 UI、无状态依赖的文件，测试网最密；`parse` 放在服务层之后，因为它依赖 sniffer 与 saver 的稳定路径。

---

## 六、等价性验证方案

1. **字符串等价**：拆分 `js_script_builder` 前后分别输出 `kDouyinSniffJs` 做 `sha1sum` 比对，必须一致。
2. **测试等价**：每个阶段跑 `flutter analyze`（0）与 `flutter test`（全绿）；测试文件一行不改。
3. **结构门禁**：`test/plan_64_test.dart` 校验：
   - 任何 `lib/**/*.dart` 不超过 400 行；
   - 文件所在目录深度不超过 5 段；
   - 每个新目录至少 2 个 Dart 文件。
4. **API 等价**：`git diff` 不出现公开类/方法签名删除；`DouyinShareApi.*`、`StatusCard.*`、`kDouyinSniffJs` 语义不变。
5. **迁移干净**：全库 `grep` 旧路径无残留；不保留转发壳文件。
6. **行为等价抽查**：diff 只允许出现 `part`/`mixin`/`class`/`import`/签名与整段方法迁移，不允许条件、阈值、文案改动。

---

## 七、风险与对策

| 风险 | 对策 |
| --- | --- |
| `part` 后私有成员跨文件不可见 | 所有 part 属于同一 library，入口文件统一 `part`，part 内不写 `import` |
| mixin 与 State 生命周期冲突 | mixin 只搬方法体，不新增字段与 `initState`；字段全留原 State |
| 入口文件移动导致 import 大面积报错 | 按文件逐个迁移，一次只动一个领域，analyze 兜底；迁移清单在提交信息中列明 |
| JS 拼装引入空格/换行差异 | 分段字符串首尾严格对齐原文本，拼接后哈希比对 |
| 循环依赖（handler ↔ server） | handler 只依赖 `AgentBridgeContext` 与 `IAgentHandler`，不 import 服务器实现 |
| 拆分后私有类型测试不可见 | `StatusCard`、`HomeWorksDelegate` 改为公开类并独立文件 |
| 拆得过细导致跳转成本上升 | 单文件不低于 25 行；纯常量/纯转发才允许合并；目录内文件数控制在 2~8 |
| 目录膨胀成"万能文件夹" | **禁止 `misc`/`common` 收集无关文件**；`common/` 只放同角色跨子领域文件 |

---

## 八、验收标准

- `lib/` 下不存在超过 400 行的 Dart 文件（`test/plan_64_test.dart` 强制）。
- 所有新增文件落在 `分层/领域/子领域/角色` 四级路径中，目录内 2~8 个文件。
- 每个巨型类拆为「门面 + 流程混入 + 协作者」，单文件单一职责。
- 旧路径无残留，不保留兼容转发壳。
- `kDouyinSniffJs` SHA-1 与拆分前一致。
- 版本号 `1.5.5+178`（`pubspec.yaml` + `lib/app_info.dart`）。
- `flutter analyze` 0 issues；`flutter test` 全绿。
- 不修改任何测试文件，不修改业务文案与阈值。

---

## 九、执行清单

1. [ ] 基线固化：JS SHA-1、行数快照、319 条测试基线。
2. [ ] `script` 分层：`services/script/{douyin,login}/chunk/`，哈希比对。
3. [ ] `share` 分层：client / model / cookie / parser{html,item,media}。
4. [ ] `update` 分层：client / model / version / parser / error。
5. [ ] `bridge` 分层：server / protocol / support / handler{9 类}。
6. [ ] `sniffer` 分层：facade / session / channel / webview / flow{3 类}。
7. [ ] `parse` 分层：page / flow{4 类} / widget{3 类} / support。
8. [ ] `history` 分层：page / flow{3 类} / widget{4 类}。
9. [ ] `shell` 分层：page / bootstrap / widget。
10. [ ] 保存页三张 sheet：page / flow / widget / debug / memory 各自成目录。
11. [ ] `update_dialog` 分层：dialog / notes / markdown。
12. [ ] 第二批 250~400 行文件继续细分到 `utils/*`、`widgets/*` 子域。
13. [ ] `test/plan_64_test.dart`：行数、目录深度、目录文件数、JS 校验。
14. [ ] 版本 1.5.5+178，analyze 0、test 全绿，旧路径 grep 零残留。

---

## 十、执行结果（2026-11-13）

- 版本：1.5.5+178。
- **全库已无超过 400 行的文件**，最大文件 `utils/url_parser.dart` 399 行，此前 11 个大文件全部拆分完毕。
- 总行数 18,827 → 19,506（新增注释与文件头），文件数由 78 增至 128。
- 关键等价性校验：
  - `kDouyinSniffJs` 由 14 个常量分片顺序拼接，拼接结果与拆分前**逐字节一致**（SHA-1 `e963f893172432d450d948089ca43c43aa950bb9`）。
  - `DouyinShareApi`、`StatusCard`、`DouyinSniffer` 的公开静态方法全部保留为一行转发。
  - 测试文件零改动。
- `flutter analyze`：0 issues。
- `flutter test`：319/319 通过。

### 10.1 拆分明细

| 原文件 | 行数 | 拆分后 | 说明 |
| --- | --- | --- | --- |
| `agent_automation_server.dart` | 1518 | 326 + 20 | 每个端点一个扩展分片（parse/save/download/history/log/media/verify/system） |
| `douyin_sniffer.dart` | 1471 | 398 + 8 | single/common/home 三组流程分片，静态纯函数留在门面 |
| `parse_page.dart` | 1365 | 301 + 8 | 单作品/主页/多作品/进度/输入 + 状态卡/登录横幅/委托 |
| `js_script_builder.dart` | 1191 | 35 + 14 | 按 JS 函数边界切片，入口只做拼接 |
| `history_page.dart` | 886 | 276 + 6 | 搜索/多选/动作/视图构建 + 卡片/筛选按钮 |
| `douyin_share_api.dart` | 756 | 206 + 8 | client / cookie / routerData / html / item / media / json / url |
| `middle_multi_work_sheet.dart` | 592 | 292 + 7 | 作品选择/分类/画质/打开/记忆/调试 + 封面组件 |
| `top_multi_home_sheet.dart` | 560 | 252 + 6 | 作者选择/画质/记忆/动作/调试 + 头像组件 |
| `bottom_media_sheet.dart` | 530 | 255 + 7 | 选择/音频/记忆/确认/预览/调试 + 资源格 |
| `update_dialog.dart` | 520 | 152 + 3 | 弹窗 / 更新日志盒 / Markdown 渲染 |
| `app_shell.dart` | 440 | 318 + 2 | 启动与登录流程 / 更新进度条 |
| `update_checker.dart` | 410 | 180 + 6 | client / model / version / atom / cleaner / error |

### 10.2 手法说明

- 巨型 State：入口保留字段与生命周期，方法按职责搬入 `part` + `extension`，跨分片调用显式 `this.`，`setState` 经 `_refresh` 入口转发，保证行为不变。
- 巨型 Service：静态解析簇拆为独立类，原类保留一行转发，测试调用的静态 API 完全不变。
- JS 字符串：仅按函数边界切片，不做任何文本加工。

### 10.3 未完成项

- PLAN 第三、四节中 250~400 行的第二批文件未细分（`url_parser`、`selection_mode_store`、`app_update_store`、`save_location_store`、`login_detector_script`、`save_location_dialog` 等），可留待 PLAN_65 继续。
