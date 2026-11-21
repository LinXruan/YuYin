# PLAN_86：删除聚合兼容壳与全域按需依赖重构（消除 media_item 与 url_parser 兼容壳）

## 1. 根因与背景

截至版本 `1.6.1+227`（commit `3405891`），全库已彻底消除所有 `part`/`part of` 指令，实现 0 part 门禁。
根据项目规范《AGENTS.md》§5.5【删除优先】：
> “重构必须删除被取代的文件、字段、模型与分支，不留双份实现。禁止兼容壳：`export` 转发、`_legacy`、`_v2`、`_old`、`Deprecated` 一律不写。删除后全库 `grep` 确认无残留引用。”

目前代码库中残留两个历史重构的兼容壳：
1. `lib/utils/url_parser.dart`（47 行）：纯静态转发门面，内部全部分发给 `DouyinUrlClassifier`、`DouyinUrlExtractor` 与 `DouyinBatchInputParser`。
2. `lib/models/media_item.dart`（28 行）：纯 `export` 转发壳，聚合导出了 20 多个分层领域模型，导致大量原本只需要单一模型的组件无差别导入了全量领域模型。

---

## 2. 目标语义与重构策略

- **终极目标**：彻底删除 `lib/utils/url_parser.dart` 与 `lib/models/media_item.dart` 两个兼容壳，实现 0 兼容壳、0 聚合 export。
- **调用直连**：
  - URL 相关操作直接调用领域工具类：`DouyinUrlClassifier`、`DouyinUrlExtractor`、`DouyinBatchInputParser` 及模型 `DouyinWorkPage`、`DouyinLinkKind`。
  - 媒体相关模型按需精确导入对应领域目录：
    - `models/single_work/media_download_item.dart`（`MediaItem` 实体）
    - `models/single_work/single_work_result.dart`
    - `models/user_home/...`
    - `models/save_page/...`
    - `models/common/work_type.dart`
- **单文件规模与门禁**：
  - 改动后所有文件严格保持 ≤400 行。
  - `flutter analyze` 0 issues，`flutter test` 100% 全绿。
  - 覆盖安装真机并通过三链路回归。

---

## 3. 分阶段实施清单与版本规划

### 阶段 1（build 228）：UrlParser 转发壳消除与直接依赖调用
- **目标**：全域替换 `UrlParser.*` 为直接调用领域类，安全删除 `lib/utils/url_parser.dart`。
- **涉及文件**：
  - 替换 19 处 `lib/` 引用与 7 处 `test/` 引用。
  - `git rm lib/utils/url_parser.dart`。
- **提交规范**：`228_pl86：消除 UrlParser 兼容壳，全域直连 URL 领域对象`（已完成，commit `6673d14`）

### 阶段 2（build 229）：MediaItem 聚合导出壳消除（按需精确导入）
- **目标**：全域替换 `models/media_item.dart` 为精确的领域模型路径，安全删除 `lib/models/media_item.dart`。
- **涉及文件**：
  - 替换 46 处 `lib/` 引用与 33 处 `test/` 引用。
  - `git rm lib/models/media_item.dart`。
- **提交规范**：`229_pl86：消除 MediaItem 聚合导出壳，全域按需精确导入领域模型`（已完成，commit `25da1f3`）

### 阶段 3（build 230）：真机端三链路实测与交接文档更新
- **目标**：覆盖安装最新 Debug 包到真机（无线 ADB），执行状态与三链路（视频、图文、主页）自动化测试，更新 `HANDOVER.md`。
- **实测结果**：
  - 状态端点：`120 Hz` 自适应高刷跟随，`version: 1.6.1+230` 正常识别。
  - 单视频链路：`https://www.douyin.com/video/7699742794776932454` 成功返回 12 个档位。
  - 单图文链路：`https://www.douyin.com/note/7701683319334910554` 成功解析 4 张图集图片。
  - 主页批量链路：`https://www.douyin.com/user/MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04?from_tab_name=main` 成功捕获作者【宁采君】及首屏 18 条作品。
- **提交规范**：`230_pl86：真机端三链路实测验证与文档更新（全库 0 兼容壳达成）`

---

## 4. 风险与防御

1. **测试断言与导入完整性**：
   - 替换 `MediaItem` 引用时，部分文件同时依赖了 `MediaType`、`SingleWorkResult`、`SaveWorkItem` 等。按需补充精确导入，避免遗漏引起未定义符号。
2. **设备状态保证**：
   - 真机测试前发送 `KEYCODE_WAKEUP` 与 `dismiss-keyguard`，确保进程处于前台活跃态。
