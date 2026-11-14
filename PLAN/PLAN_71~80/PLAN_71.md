# PLAN_71：整块对象化拆分与目录分层整治（版本 1.5.5+185）

> 目标：把 PLAN_64 遗留的「第二批 250~400 行文件」全部按**内聚对象**拆开，同时把 `utils/services/pages/widgets` 根目录收拢到领域子目录，超 8 文件的目录再分层，补上行数与目录门禁。
> 原则：拆分单元是「整块对象」而非「行数块」；行为严格等价；删除优先，不留兼容壳；层次深度按 `分层/领域/子领域/角色`。

---

## 一、根因分析

### 1.1 历史遗留（PLAN_64 §10.3 明确未完成）

PLAN_64 已消灭全部 >400 行巨石，但 §10.3 记录「250~400 行第二批未细分，可留待 PLAN_65 继续」。PLAN_65~70 全部投入保存页逻辑重构，这批文件**一次都没拆**，部分还在后续迭代中回涨：

| 文件 | 行数 | 现状 |
| --- | --- | --- |
| `lib/utils/url_parser.dart` | 399 | 静态工具类，15 个方法平铺 |
| `lib/services/douyin_sniffer.dart` | 394 | 门面，20+ 个可空字段与 Timer/Completer 散落 |
| `lib/utils/app_update_store.dart` | 346 | 静态 Store，`startDownload` 单方法 137 行 |
| `lib/utils/save_location_store.dart` | 342 | `SaveLocationConfig` 单类 210 行（字段+派生+序列化+相等性） |
| `lib/services/login_detector_script.dart` | 334 | 枚举/模型与整段登录 JS 字符串混放 |
| `lib/services/agent_automation_server.dart` | 333 | 门面，88 行 if-else 路由 + 序列化 + 58 行测试基准常量 |
| `lib/widgets/save_location_dialog.dart` | 328 | 单 StatelessWidget，`build` 125 行、`_buildLocationCard` 139 行 |
| `lib/widgets/save_page/bottom_media_widgets.dart` | 313 | 5 个组件塞在一个文件 |
| `lib/utils/history_thumbnail_cache.dart` | 301 | 静态缓存，索引/下载/统计/清理混在一起 |
| `lib/pages/parse_page.dart` | 296 | `build` 138 行内联 |
| `lib/services/sniffer/common/message_flow.dart` | 286 | `_onJavaScriptMessage` 单方法 132 行 |
| `lib/pages/history/widget/card/history_card.dart` | 280 | 卡片 + 4 个缩略图构建方法 |
| `lib/pages/history_page.dart` | 276 | `build` 185 行内联 |
| `lib/services/selection/save_selection_session.dart` | 273 | 工厂 + 查询 + 生命周期 + 构建 helper 全在一个类 |
| `lib/services/selection/debug/selection_debug_bridge.dart` | 273 | `run` 71 行 + 多个 category/filter 分支 |
| `lib/pages/app_shell.dart` | 262 | `initState` 55 行 + `build` 132 行 |
| `lib/services/bridge/handler/save/selection_handler.dart` | 261 | 分发 + `_loadSelection` 165 行 |
| `lib/services/bridge/parse/parse_handler.dart` | 259 | `_handleParse` 单方法 193 行 |

### 1.2 目录违规（AGENTS §5.2「同目录 2~8 个 .dart」）

| 目录 | 文件数 | 问题 |
| --- | --- | --- |
| `lib/utils` | 19 | 根目录平铺，7 个超目标文件全在此 |
| `lib/services/script/douyin/chunk` | 14 | 未按 JS 职责再分层 |
| `lib/models/save_page/selection` | 11 | 状态/视图/种子混放 |
| `lib/services` | 10 | 门面与领域服务全部堆在根 |
| `lib/pages` | 8 | 页面入口全部堆在根 |

### 1.3 门禁缺失

PLAN_64 §六承诺的 `test/plan_64_test.dart`（行数 ≤400、目录深度、目录文件数）**从未落地**，`test/` 中不存在任何行数或目录门禁。250 行目标值无人执行，是这批文件长期泄漏的根本原因。

---

## 二、目标语义

### 2.1 拆分单元是「整块对象」

一个文件承载一个内聚对象：拥有自己的状态、行为、生命周期，对外只暴露契约。判定标准：

- **状态内聚**：同一对象的字段与操作它的方法在同一文件；不允许把 20 个 `bool?_Timer?` 散在门面里。
- **职责单一**：一个对象只回答一个问题（路由、序列化、缓存索引、下载、派生路径…）。
- **禁止横切摊派**：不得把同一类方法机械拆到多个文件凑行数。
- **门面只做分发**：门面保留字段与生命周期，具体行为委托给领域对象。

本次落地的整块对象：

| 对象 | 取代的散落逻辑 |
| --- | --- |
| `SnifferTaskState` | `DouyinSniffer` 中 20+ 个任务标志位/定时器/Completer |
| `AgentRouter` | `_handleRequest` 的 88 行 if-else 链 |
| `BridgeSerializers` | `_serializeWorkSaveResult`/`_serializeItems`/`_qualityModeFrom` |
| `SaveLocationConfig` + `SaveLocationPaths` + `SaveLocationJson` | 210 行巨型 Config 的派生与序列化 |
| `SelectionSessionFactory` / `SelectionSessionQuery` | 273 行会话类的工厂与查询 |
| `DouyinUrlClassifier` / `DouyinUrlExtractor` / `DouyinBatchInputParser` | 399 行 `UrlParser` |
| `AppUpdateDirectory` / `AppUpdateDownloader` | 346 行 `AppUpdateStore` |
| `ThumbnailIndex` / `ThumbnailDownloader` / `ThumbnailMaintenance` | 301 行 `HistoryThumbnailCache` |

### 2.2 层次深度

统一 `lib/<分层>/<领域>/<子领域>/<角色>/<文件>.dart`，最深层 5 段（不含 `lib`）。每个目录 2~8 个 `.dart`；单文件目录不新建（平铺到父目录）。

### 2.3 等价性约束

- **不修改行为**：不修 bug、不改时序、不改阈值、不改文案、不改日志文本。
- **不改公开符号语义**：类名、构造参数、静态方法签名不变；仅允许文件路径与类拆分导致的 import 变更。
- **测试断言不改**：测试文件的 `import` 路径可同步修改，断言一律不动。
- **JS 逐字节等价**：`kDouyinSniffJs` 拼接结果 SHA-1 必须与拆分前一致（当前基线 `e963f893172432d450d948089ca43c43aa950bb9`，需重新采样确认）。

---

## 三、目标目录结构

```
lib/
├── models/
│   ├── url/                         douyin_link_kind
│   ├── update/                      app_update_status, local_apk_info
│   ├── savelocation/                save_location_config, paths, json
│   └── save_page/selection/
│       ├── state/                   aggregate_state, selection_state, quality_indicator, quality_preference
│       ├── view/                    author/work/resource/terminal view
│       └── seed/                    terminal_seed, selection_source, selected_work
├── utils/
│   ├── url/                         classifier, extractor, batch_input_parser, launcher, parse_utils
│   ├── thumbnail/                   index, downloader, maintenance, facade
│   ├── update/                      directory, downloader, store
│   ├── savelocation/                store
│   ├── history/                     store, query
│   ├── save/                        file_name_formatter, home_save_path, author_folder_name
│   ├── settings/                    download_settings_store, theme_store, display_mode_service, video_quality_utils
│   ├── memory/                      terminal_memory_store
│   ├── debug/                       log_controller, save_page_debug_store
│   ├── network_detector.dart        单文件平铺
│   └── login_state_store.dart       单文件平铺
├── services/
│   ├── sniffer/{facade,session,lifecycle,channel,contract,flow/...}
│   ├── bridge/{server,protocol,reference,handler,...}
│   ├── script/{douyin/{chunk/core,chunk/media,chunk/scan,chunk/home},login/{chunk}}
│   ├── share/{client,parser/{html,item,media},model,cookie}
│   ├── update/{client,model,version,parser,error}
│   ├── media/                       audio_preview_service, video_downloader, media_saver
│   ├── selection/{session,flow,internal,debug}
│   └── ... 既有 single_work/user_home/multi_work/batch_work/history
├── pages/
│   ├── parse/{page,flow/{single,home,multi,common},widget/{status,banner,input}}
│   ├── history/{page,flow/{search,selection,action,view},widget/{card,filter,banner,list}}
│   ├── shell/{page,flow,widget}
│   ├── settings/                    settings_page, download_settings_page
│   ├── about_page.dart              单文件平铺
│   ├── debug_page.dart              单文件平铺
│   └── login_webview_page.dart      单文件平铺
└── widgets/
    ├── savelocation/                dialog, card, group_title, pickers
    ├── save_page/bottom/widget/     audio_bar, scrub_bar, live_tile, audio_tile
    ├── update/{dialog,notes,markdown}
    └── log_panel.dart               单文件平铺
```

---

## 四、新增文件清单（按阶段，预估行数 ≤250）

### 阶段 1：`utils/url`（原 399 行 `url_parser.dart`）

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/models/url/douyin_link_kind.dart` | 枚举与值对象 | 60 | url_parser:1-56 |
| `lib/utils/url/url_classifier.dart` | 分类纯函数 | 100 | 223-253,332-389 |
| `lib/utils/url/url_extractor.dart` | 提取纯函数 | 115 | 217-222,254-331,390-399 |
| `lib/utils/url/batch_input_parser.dart` | 批量输入解析 | 145 | 77-216 |
| `lib/utils/url/url_launcher_util.dart` | 外部跳转 | 45 | 根目录移入 |
| `lib/utils/url/parse_utils.dart` | JSON 正整数 | 7 | 根目录移入 |

### 阶段 2：`utils/thumbnail`（原 301 行）

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/utils/thumbnail/thumbnail_cache_index.dart` | 索引与查找 | 120 | 94-179 |
| `lib/utils/thumbnail/thumbnail_downloader.dart` | 下载执行 | 90 | 60-74,180-255 |
| `lib/utils/thumbnail/thumbnail_maintenance.dart` | 统计与清理 | 55 | 75-93,256-301 |
| `lib/utils/thumbnail/history_thumbnail_cache.dart` | 门面 | 70 | 17-59,委托 |

### 阶段 3：`utils/update`（原 346 行）

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/models/update/app_update_status.dart` | 状态模型 | 45 | 12-52 |
| `lib/models/update/local_apk_info.dart` | 本地 APK 模型 | 30 | 53-65,179-190 |
| `lib/utils/update/app_update_directory.dart` | 目录与扫描 | 90 | 93-178 |
| `lib/utils/update/app_update_downloader.dart` | 下载执行 | 155 | 191-346 |
| `lib/utils/update/app_update_store.dart` | 门面 | 70 | 66-92,委托 |

### 阶段 4：`utils/savelocation`（原 342 行）

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/models/savelocation/save_location_config.dart` | 不可变值对象 | 130 | 10-62,113-219 |
| `lib/models/savelocation/save_location_paths.dart` | 路径派生 extension | 60 | 63-112 |
| `lib/models/savelocation/save_location_json.dart` | 序列化 extension | 45 | 146-183 |
| `lib/utils/savelocation/save_location_store.dart` | 门面 + 持久化 | 120 | 220-342 |

### 阶段 5：`utils` 根收拢

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/utils/save/file_name_formatter.dart` | 文件名 | 126 | 移入 |
| `lib/utils/save/home_save_path.dart` | 主页路径 | 72 | 移入 |
| `lib/utils/save/author_folder_name.dart` | 作者文件夹 | 25 | 移入 |
| `lib/utils/settings/download_settings_store.dart` | 下载设置 | 180 | 移入 |
| `lib/utils/settings/theme_store.dart` | 主题 | 103 | 移入 |
| `lib/utils/settings/display_mode_service.dart` | 显示模式 | 102 | 移入 |
| `lib/utils/settings/video_quality_utils.dart` | 画质工具 | 96 | 移入 |
| `lib/utils/history/history_store.dart` | 历史持久化 | 150 | 246 行拆出 |
| `lib/utils/history/history_query.dart` | 模糊检索 | 100 | 246 行拆出 |
| `lib/utils/memory/terminal_memory_store.dart` | 记忆 | 131 | 移入 |
| `lib/utils/debug/log_controller.dart` | 日志 | 62 | 移入 |
| `lib/utils/debug/save_page_debug_store.dart` | 调试快照 | 23 | 移入 |

### 阶段 6：`services` 根收拢 + 三个门面对象化

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/services/sniffer/facade/douyin_sniffer.dart` | 门面 | 120 | 394 行拆出 |
| `lib/services/sniffer/session/sniffer_task_state.dart` | 任务状态对象 | 140 | 80-116 字段收敛 |
| `lib/services/sniffer/lifecycle/sniffer_lifecycle_flow.dart` | 生命周期 part | 130 | 236-370 |
| `lib/services/sniffer/channel/sniffer_channel_parser.dart` | 通道纯函数 | 60 | 246-280 |
| `lib/services/sniffer/contract/sniffer_contract_impl.dart` | 契约实现 part | 50 | 370-394 |
| `lib/services/bridge/server/agent_automation_server.dart` | 门面 | 120 | 333 行拆出 |
| `lib/services/bridge/server/agent_router.dart` | 路由表对象 | 90 | 137-224 |
| `lib/services/bridge/protocol/bridge_serializers.dart` | 序列化对象 | 70 | 225-257 |
| `lib/services/bridge/protocol/bridge_request.dart` | 请求解析 | 30 | 316-328 |
| `lib/services/bridge/protocol/bridge_response.dart` | 响应写出 | 20 | 329-333 |
| `lib/services/bridge/reference/reference_fixtures.dart` | 测试基准常量 | 75 | 258-315 |
| `lib/services/script/login/login_detector_script.dart` | 拼接入口 | 60 | 334 行拆出 |
| `lib/services/script/login/chunk/js_login_models.dart` | 登录模型 | 40 | 4-36 |
| `lib/services/script/login/chunk/js_login_probe.dart` | 登录探测 JS | 120 | 字符串分片 |
| `lib/services/script/login/chunk/js_login_report.dart` | 登录上报 JS | 120 | 字符串分片 |
| `lib/services/share/client/douyin_share_api.dart` | 分享 API | 204 | 移入 |
| `lib/services/media/audio_preview_service.dart` | 音频预览 | 204 | 移入 |
| `lib/services/media/video_downloader.dart` | 视频下载 | 190 | 移入 |
| `lib/services/media/media_saver.dart` | 媒体保存 | 123 | 移入 |
| `lib/services/update/client/update_checker.dart` | 更新检查 | 160 | 移入 |
| `lib/services/update/app_installer.dart` | APK 安装 | 61 | 移入 |
| `lib/services/script/douyin/douyin_sniff_script.dart` | JS 拼接入口 | 37 | 移入 |

### 阶段 7：`pages` 根收拢

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/pages/shell/page/app_shell.dart` | 页面入口 | 120 | 262 行拆出 |
| `lib/pages/history/page/history_page.dart` | 页面入口 | 140 | 276 行拆出 |
| `lib/pages/parse/page/parse_page.dart` | 页面入口 | 150 | 296 行拆出 |
| `lib/pages/settings/settings_page.dart` | 设置页 | 204 | 移入 |
| `lib/pages/settings/download_settings_page.dart` | 下载设置页 | 81 | 移入 |

### 阶段 8：`widgets` 根收拢

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/widgets/savelocation/save_location_dialog.dart` | 弹窗骨架 | 70 | 328 行拆出 |
| `lib/widgets/savelocation/save_location_card.dart` | 位置卡片 | 140 | 190-328 |
| `lib/widgets/savelocation/save_location_group_title.dart` | 分组标题 | 25 | 176-189 |
| `lib/widgets/savelocation/save_location_pickers.dart` | 目录选择 | 50 | 19-49 |
| `lib/widgets/update/dialog/update_dialog.dart` | 更新弹窗 | 168 | 移入 |

### 阶段 9：组件与页面内部拆分

| 路径 | 角色 | 行数 | 来源 |
| --- | --- | --- | --- |
| `lib/pages/parse/widget/input/parse_input_section.dart` | 输入区 | 110 | parse_page.build |
| `lib/pages/parse/widget/status/parse_status_section.dart` | 状态区 | 80 | parse_page.build |
| `lib/pages/history/widget/list/history_list_view.dart` | 列表区 | 90 | history_page.build |
| `lib/pages/history/widget/banner/history_toolbar.dart` | 搜索/多选栏 | 70 | history_page.build |
| `lib/pages/shell/widget/shell_scaffold.dart` | 页面骨架 | 90 | app_shell.build |
| `lib/pages/history/widget/card/history_card_thumbnail.dart` | 缩略图组件 | 120 | history_card:140-280 |
| `lib/pages/history/widget/card/history_thumbnail_loader.dart` | 缩略图加载 | 40 | history_card:189-242 |
| `lib/widgets/save_page/bottom/widget/media_audio_player_bar.dart` | 音频播放条 | 140 | bottom_media_widgets:7-143 |
| `lib/widgets/save_page/bottom/widget/scrubrable_progress_bar.dart` | 进度条 | 110 | 144-248 |
| `lib/widgets/save_page/bottom/widget/media_live_video_tile.dart` | 实况格 | 40 | 249-280 |
| `lib/widgets/save_page/bottom/widget/media_audio_tile.dart` | 音频格 | 40 | 281-313 |
| `lib/services/sniffer/channel/message_log_flow.dart` | 日志分流 | 50 | message_flow |
| `lib/services/sniffer/channel/message_login_flow.dart` | 登录分流 | 60 | message_flow |
| `lib/services/sniffer/channel/message_result_flow.dart` | 结果分流 | 120 | message_flow |
| `lib/services/bridge/handler/parse/status_handler.dart` | status 端点 | 60 | parse_handler:6-65 |
| `lib/services/bridge/handler/parse/parse_executor.dart` | parse 执行 | 100 | parse_handler:66-259 |
| `lib/services/bridge/handler/save/selection_state_handler.dart` | 状态端点 | 50 | selection_handler:5-95 |
| `lib/services/bridge/handler/save/selection_load_handler.dart` | 加载端点 | 140 | selection_handler:96-261 |
| `lib/services/selection/session/session_factory.dart` | 会话工厂 | 90 | save_selection_session:72-133,233-273 |
| `lib/services/selection/session/session_query.dart` | 会话查询 | 90 | 159-206 |
| `lib/services/selection/debug/command_parser.dart` | 命令解析 | 50 | selection_debug_bridge:62-133 |
| `lib/services/selection/debug/category_flow.dart` | 分类命令 | 80 | 143-169 |
| `lib/services/selection/debug/filter_flow.dart` | 过滤命令 | 80 | 170-243 |

### 阶段 10：门禁

| 路径 | 角色 | 行数 |
| --- | --- | --- |
| `test/plan_71_structure_test.dart` | 行数/目录/深度门禁 | 120 |

---

## 五、删除清单

> 「移入」表示原路径删除、内容进入新路径；「拆分」表示原文件删除、内容重组为多个新文件。

| 路径 | 行数 | 处理 |
| --- | --- | --- |
| `lib/utils/url_parser.dart` | 399 | 拆分 |
| `lib/utils/url_launcher_util.dart` | 45 | 移入 `utils/url/` |
| `lib/utils/parse_utils.dart` | 7 | 移入 `utils/url/` |
| `lib/utils/history_thumbnail_cache.dart` | 301 | 拆分 |
| `lib/utils/app_update_store.dart` | 346 | 拆分 |
| `lib/utils/save_location_store.dart` | 342 | 拆分 |
| `lib/utils/file_name_formatter.dart` | 126 | 移入 `utils/save/` |
| `lib/utils/home_save_path.dart` | 72 | 移入 `utils/save/` |
| `lib/utils/author_folder_name.dart` | 25 | 移入 `utils/save/` |
| `lib/utils/download_settings_store.dart` | 180 | 移入 `utils/settings/` |
| `lib/utils/theme_store.dart` | 103 | 移入 `utils/settings/` |
| `lib/utils/display_mode_service.dart` | 102 | 移入 `utils/settings/` |
| `lib/utils/video_quality_utils.dart` | 96 | 移入 `utils/settings/` |
| `lib/utils/history_store.dart` | 246 | 拆分 |
| `lib/utils/terminal_memory_store.dart` | 131 | 移入 `utils/memory/` |
| `lib/utils/log_controller.dart` | 62 | 移入 `utils/debug/` |
| `lib/utils/save_page_debug_store.dart` | 23 | 移入 `utils/debug/` |
| `lib/services/douyin_sniffer.dart` | 394 | 拆分 + 移入 `sniffer/facade/` |
| `lib/services/login_detector_script.dart` | 334 | 拆分 |
| `lib/services/agent_automation_server.dart` | 333 | 拆分 + 移入 `bridge/server/` |
| `lib/services/douyin_share_api.dart` | 204 | 移入 `share/client/` |
| `lib/services/audio_preview_service.dart` | 204 | 移入 `media/` |
| `lib/services/video_downloader.dart` | 190 | 移入 `media/` |
| `lib/services/update_checker.dart` | 160 | 移入 `update/client/` |
| `lib/services/media_saver.dart` | 123 | 移入 `media/` |
| `lib/services/app_installer.dart` | 61 | 移入 `update/` |
| `lib/services/js_script_builder.dart` | 37 | 移入 `script/douyin/` |
| `lib/services/sniffer/common/message_flow.dart` | 286 | 拆分 |
| `lib/services/bridge/parse/parse_handler.dart` | 259 | 拆分 |
| `lib/services/bridge/handler/save/selection_handler.dart` | 261 | 拆分 |
| `lib/services/selection/save_selection_session.dart` | 273 | 拆分 |
| `lib/services/selection/debug/selection_debug_bridge.dart` | 273 | 拆分 |
| `lib/pages/app_shell.dart` | 262 | 拆分 + 移入 `shell/page/` |
| `lib/pages/history_page.dart` | 276 | 拆分 + 移入 `history/page/` |
| `lib/pages/parse_page.dart` | 296 | 拆分 + 移入 `parse/page/` |
| `lib/pages/settings_page.dart` | 204 | 移入 `pages/settings/` |
| `lib/pages/download_settings_page.dart` | 81 | 移入 `pages/settings/` |
| `lib/widgets/save_location_dialog.dart` | 328 | 拆分 |
| `lib/widgets/update_dialog.dart` | 168 | 移入 `update/dialog/` |
| `lib/pages/history/widget/card/history_card.dart` | 280 | 拆分 |
| `lib/widgets/save_page/bottom_media_widgets.dart` | 313 | 拆分 |

### 5.1 超 8 目录再分层（移动）

| 目录 | 现状 | 目标 |
| --- | --- | --- |
| `models/save_page/selection` | 11 个 | `state/`(4) + `view/`(4) + `seed/`(3) |
| `services/script/douyin/chunk` | 14 个 | `core/`(4) + `media/`(4) + `scan/`(3) + `home/`(3) |

> **JS 分片铁律**：chunk 仅移动路径，`douyin_sniff_script.dart` 中 14 个 import 与 `const` 拼接顺序**必须保持原序**；拆分后 `kDouyinSniffJs` 的 SHA-1 与基线逐字节一致。

---

## 六、执行步骤与验证

| 步骤 | 内容 | 验证 |
| --- | --- | --- |
| 0 | 基线固化：`sha1sum` 采样 `kDouyinSniffJs`、记录 18 文件行数、`flutter test` 全绿 | 记录基线 |
| 1 | `utils/url` 拆分，改 23 处调用点 | analyze 0、`url_parser_test` 全绿、grep 旧类零残留 |
| 2 | `utils/thumbnail` 拆分，改 9 处调用点 | analyze 0、相关测试全绿 |
| 3 | `utils/update` 拆分，改 9 处调用点 | analyze 0、`app_update_store_test` 全绿 |
| 4 | `utils/savelocation` 拆分，改 14 处调用点 | analyze 0、`save_location_store_test` 全绿 |
| 5 | `utils` 根收拢 + `history_store` 拆分 | analyze 0、test 全绿、`utils` 根 ≤2 文件 |
| 6 | `services` 根收拢 + sniffer/bridge/login 三个门面对象化 | analyze 0、test 全绿、SHA-1 一致 |
| 7 | `pages` 根收拢 + 三个 part 根路径迁移 | analyze 0、test 全绿 |
| 8 | `widgets` 根收拢 + `save_location_dialog` 拆分 | analyze 0、`save_location_dialog_test` 全绿 |
| 9 | 组件/页面/build 内部拆分 + 选择模型重分层 | analyze 0、test 全绿、全库无 >250 |
| 10 | 落 `test/plan_71_structure_test.dart`，版本 1.5.5+185，更新 AGENTS 现状 | 门禁测试通过、analyze 0、test 全绿 |

每阶段独立 commit（`185_pl71：<阶段>拆分`），可单独 revert。

### 6.1 part 路径迁移清单（高风险，逐项核对）

| 入口文件（旧 → 新） | part 声明变更 |
| --- | --- |
| `services/douyin_sniffer.dart` → `sniffer/facade/` | `sniffer/x` → `../x`；part 内 `part of '../../douyin_sniffer.dart'` → `part of '../facade/douyin_sniffer.dart'` |
| `services/agent_automation_server.dart` → `bridge/server/` | `bridge/x` → `../x`；part of → `../server/agent_automation_server.dart` |
| `pages/parse_page.dart` → `parse/page/` | `parse/x` → `../x`；part of → `../page/parse_page.dart` |
| `pages/history_page.dart` → `history/page/` | `history/x` → `../x`；part of → `../page/history_page.dart` |
| `pages/app_shell.dart` → `shell/page/` | `shell/x` → `../x`；part of → `../page/app_shell.dart` |

---

## 七、验收清单

- [ ] 全库 `lib/**/*.dart` 无文件超过 **250 行**（纯 UI 目标 ≤200）。
- [ ] `utils/services/pages/widgets` 根目录不再堆积领域文件；`services` 根为 0 个 `.dart`。
- [ ] `utils` 根仅保留 `network_detector.dart`、`login_state_store.dart` 两个平铺文件。
- [ ] 每个目录 `.dart` 文件数在 2~8 之间；深度 ≤5 段。
- [ ] `SnifferTaskState`、`AgentRouter`、`BridgeSerializers`、`SelectionSessionFactory/Query`、`SaveLocationPaths/Json`、`AppUpdateDirectory/Downloader`、`ThumbnailIndex/Downloader/Maintenance` 均为独立对象。
- [ ] `kDouyinSniffJs` SHA-1 与基线一致。
- [ ] 旧路径全库 grep 零残留；无 `_legacy`/`_v2`/转发壳。
- [ ] `test/plan_71_structure_test.dart` 通过（行数、目录数、深度）。
- [ ] `flutter analyze` 0 issues；`flutter test` 全绿。
- [ ] 版本 `1.5.5+185`（`pubspec.yaml` + `lib/app_info.dart`），AGENTS 现状段落更新。
- [ ] 测试断言未改动，仅同步 import 路径。

---

## 八、风险与回退

| 风险 | 对策 |
| --- | --- |
| part 根路径迁移导致编译失败 | 每阶段只动一个 part 根；analyze 兜底；part of 与 part 声明成对修改 |
| `SnifferTaskState` 字段收敛改变时序 | 字段语义一对一映射；不改赋值时机；逐步替换 `_field` → `_state.field`，每文件验证 |
| JS 分片移动改变拼接顺序 | 只改 import 路径不改顺序；SHA-1 逐字节比对 |
| 删除 `UrlParser` 引发 23 处调用点遗漏 | 先加新类，再全库 grep 替换，最后删旧类；analyze 兜底 |
| 目录迁移打断 `part of` 相对路径 | 迁移清单逐项核对；analyze 会直接报错 |
| `kReference167/168/169` 移动后测试找不到 | 常量名不变，仅 import 路径变；测试同步改 import |
| 一次改动过大难定位 | 10 阶段 10 次 commit，每阶段 analyze+test 门禁 |
| 拆得过细跳转成本上升 | 单文件 ≥25 行；纯常量/纯转发才合并；目录 2~8 文件 |

### 回退

按阶段 revert 对应 commit 即可；阶段 0 已固化基线行数与 SHA-1，可随时对照。
