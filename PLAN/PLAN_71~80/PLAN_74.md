# PLAN_74：未登录主页首屏解析（1.5.6+189）

> 定稿范围：未登录只解析首屏（约 18~26 条），不追求翻页，不做浏览器指纹伪装。
> 状态：代码完成，analyze 0 issues、367 测试全绿、debug 包已编译；真机验证由用户执行。

## 一、背景结论

| 场景（隐藏 WebView，未登录） | 接口 | 首屏 |
| --- | --- | --- |
| 原生（UA=Windows Chrome，`navigator.platform=Linux aarch64`） | 200 + content-length 0 | 0 条，"服务异常" |
| 只对齐 `navigator.platform='Win32'` | status_code 0 | 18~26 条 |
| 真 Chrome 匿名 | 正常 | 44 条，可翻到 133+ |

- 卡点一（已解决）：UA 与 `navigator.platform` 不一致 → 作品接口返回空 body。
- 卡点二（放弃绕过）：首屏之后抖音只给受限匿名版页面，列表底部渲染「登录后查看更多作品 / 立即登录」，不再发起第二次 `aweme/post`。UA 版本、UA-CH、屏幕尺寸、删除墙节点、清理风控 Cookie、重放带签名的请求均已验证无效。

## 二、方案

### 1. 平台对齐补丁（`chunk/js_platform_patch.dart`，~20 行）

`navigator.platform` 对齐为 `Win32`，拼在 `kDouyinSniffJs` 最前面，`onPageStarted` 即注入，早于页面首个数据请求。

### 2. 拆登录门禁（7 处）

| 文件 | 处理 |
| --- | --- |
| `services/sniffer/home/home_sniff_flow.dart` | 未登录 → 日志「未登录模式：仅解析首屏作品」，继续 |
| `services/sniffer/home/profile_sniff_flow.dart` | 同上（作者信息） |
| `pages/parse/flow/home/home_parse_flow.dart` | 去掉提前 return，改为日志 |
| `services/bridge/parse/parse_handler.dart` | 删除 403 分支 |
| `services/bridge/parse/parse_homes_handler.dart` | 删除 403 分支 |
| `services/bridge/parse/parse_profile_handler.dart` | 删除 403 分支 |
| `services/bridge/save/save_home_handler.dart` | 删除 403 分支（首屏作品可保存） |

### 3. 首屏语义

- JS：未登录（`S.loginReported === false`）时空闲阈值 12 → 4，约 4~6 秒收尾，完成原因「未登录仅首屏，已停止翻页」。
- 上报：`user_home_result` 增加 `partial`。
- 模型：`UserHomeResult.partial`（默认 false），`toMap` 透出。
- 日志：`主页捕获成功（未登录首屏，主页标注 N 条）：作者【X】，共 M 条作品`；解析页再补一条「未登录仅获取首屏 M 条（主页标注 N 条），登录后可获取全部」。

### 4. 收尾

- 版本 `1.5.6+189`（pubspec + app_info 同步）
- 删除 plan_50/51/52 三条「未登录返回 403」过期断言
- 新增 `test/plan_74_test.dart`（补丁顺序、首屏收尾、partial 序列化、不再 403）

## 三、验证

- `flutter analyze` 0 issues；`flutter test` 367 全绿；debug 包已编译
- 同类补丁的真机历史记录（1.5.6+189 实验包）：单主页 18 条 / 三主页 18、20、21 条 / 作者信息正常

## 四、已知边界

- 未登录最多拿到首屏，主页标注总数（如 308）与实际条数不一致属预期，靠 `partial` 与日志提示。
- 抖音若再调整该接口的环境校验，首屏可能退回空结果，此时提示用户登录即可。
- 登录路径不依赖该补丁，行为不变。

## 五、回退

删除 `js_platform_patch.dart` 与 `douyin_sniff_script.dart` 的拼接行、恢复 7 处门禁，即可回到 1.5.6+188 行为。
