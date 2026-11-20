# PLAN_79：Wave 3 准确度与体验闭环

- 版本：`1.5.10+194`
- 主题：链接识别纠错、失败可重试、进度与状态表达准确
- 前置：`PLAN_78`

## 一、根因

1. `lib/utils/url/url_classifier.dart:80-84`：不支持 `iesdouyin.com`。
2. `lib/utils/url/batch_input_parser.dart:114-152`：`modal_id` 识别顺序靠后，主页作品链接被误折叠；短链判定过宽。
3. `lib/utils/network_detector.dart:30-53`：串行探测且不排除 link-local，断网时 4 秒假死。
4. `lib/pages/parse/widget/status/status_card.dart:34-36`：状态为弱类型字符串，批量部分失败无法一键重试；单作者进度条开局即 100%。
5. `lib/pages/parse/flow/common/save_page_flow.dart`：中层打开未解析作品失败只写后台日志。
6. 历史页缺少「重新解析」与媒体类型筛选；冷启动已关闭横幅闪现；音频错误态与拖动抖动。

## 二、目标语义

| 场景 | 目标语义 |
| --- | --- |
| 链接 | `iesdouyin.com` / `modal_id` / 短链均按真实语义归类，不误折叠 |
| 网络 | 并发探测 + 排除 link-local，断网 1.5 秒内给出结论 |
| 状态 | `ParseStatus` 强类型（idle/running/success/partialFailure/failure），失败项可一键重试 |
| 历史 | 支持一键重新解析与媒体类型筛选，失败有页内反馈 |
| 音频 | 错误态可见、拖动 200ms 防抖、暂停恢复不抖动 |

## 三、文件清单

| 文件 | 变更 | 预估行数 |
| --- | --- | --- |
| `lib/models/parse/parse_status.dart` | 新增：强类型状态与失败项 | 约 90 |
| `lib/utils/url/url_classifier.dart` | 改：补 `iesdouyin.com` | ≤110 |
| `lib/utils/url/batch_input_parser.dart` | 改：`modal_id` 优先 | ≤160 |
| `lib/utils/network_detector.dart` | 改：并发探测 | ≤90 |
| `lib/pages/parse/widget/status/status_card.dart` | 改：强类型 + 重试按钮 | ≤120 |
| `lib/pages/history/widget/*` | 改：重新解析入口与筛选 | 按目录拆分 |
| `test/plan_79_ux_test.dart` | 新增 | 约 240 |

## 四、验收

- [ ] `iesdouyin.com`、`?modal_id=`、短链、纯文字均按预期分类，单测覆盖。
- [ ] 断网检测 ≤1.5 秒；批量部分失败可一键重试且只重试失败项。
- [ ] 单作者批量进度从 0 连续增长；中层打开失败在弹窗内提示。
- [ ] `analyze` 0 issues、`test` 全绿、真机验收通过。
---

## 五、落地状态（2026-11-20，1.5.10+194）

已落地：
- `iesdouyin.com` 短链归入抖音域名，批量粘贴不再漏识别。
- `?modal_id=` 作品优先于 `/user/` 主页判定，去重键与分类一致。
- 网络探测并发解析 douyin/baidu 并排除 link-local，断网结论更快。
- 主页批量保存进度改为作品粒度，单作者不再开局 100%。

未落地（顺延）：
- `ParseStatus` 强类型与失败项一键重试、中层失败页内提示。
- 历史页「重新解析」、媒体类型筛选、音频错误态/拖动防抖、图片全屏滑动等体验项。
