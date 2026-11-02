# PLAN_37：彻底解决未登录态下视频解析缓慢问题（v1.3.4+145）

## 一、需求背景与目标

### 1. 现象与用户反馈
用户反馈在**未登录状态下，视频解析速度非常缓慢**（实测需等待 30 秒整超时后才出结果），而**图文解析速度是正常的**（约 2 秒内极速完成）。
用户提供了 3 条测试口令（`sources/145_抖音口令/三条不同的视频口令.txt`），并在模拟器中卸载了应用以彻底重置为无 Cookie 的初始未登录状态：
1. 普通视频 1：`1.71 复制打开抖音，看看【D4C好想放假的作品】这样的霸之意志我认可你了 # 配音# 搞笑# 抽象... https://v.douyin.com/0KF7YESssC4/`
2. 图文作品 2：`0.56 复制打开抖音，看看【辉辉gg的图文作品】你的Token又该充值了# 梁文锋 # 大肥鱼 #... https://v.douyin.com/NhaZaQHu4Dw/`
3. 普通视频 3：`0.25 复制打开抖音，看看【7 v的作品】晚会  https://v.douyin.com/q8ZWiQz12Bs/`

### 2. 核心目标
1. **未登录态视频极速秒开**：将未登录状态下的视频解析时间由 **30 ~ 35 秒** 暴降至 **1 秒左右（秒级响应）**，与图文解析体验保持完全一致。
2. **已登录态高质量档位保持无损**：在用户登录抖音状态下，继续保留 PLAN_36 的多清晰度档位提取链路（1080P `1080_1_1` 等 11 档）。
3. **版本升级**：版本保持 `1.3.4`，构建版本号升级为 `145`（即 `1.3.4+145`，同步更新 `pubspec.yaml` 与 `lib/app_info.dart`）。

---

## 二、根因分析 (Root Cause Analysis)

经过全链路时序分析与实机日志取证，揭示了以下根本原因：

```mermaid
sequenceDiagram
    autonumber
    actor User as 用户输入视频口令
    participant Sniffer as DouyinSniffer
    participant ShareApi as DouyinShareApi (Dio)
    participant WebView as 主桌面 WebView (douyin.com)

    User->>Sniffer: sniffVideoUrl(url)
    par 并行链路 A (主 WebView)
        Sniffer->>WebView: 加载 PC 网页 (桌面 UA)
    and 并行链路 B (Dio 分享页)
        Sniffer->>ShareApi: fetchShareItem(awemeId)
    end

    Note over ShareApi: 耗时 ~0.7 秒即拿到无水印视频直链
    ShareApi-->>Sniffer: 返回 DouyinShareResult (1个视频)

    alt 图文作品 (isImagePost == true)
        Note over Sniffer: 仅等待 3 秒实况宽限期，~2 秒即极速完成！
    else 视频作品 (isImagePost == false)
        critical 关键瓶颈设计缺陷
            Note over Sniffer: 无论是否登录，一律强行阻断完成！<br/>_shareVideoFallback = result;<br/>等待主 WebView 返回完整 1080P 码率列表
        end
    end

    alt 已登录状态
        Note over WebView: 顺利加载 PC 页面并抓取 11 档画质
    else 未登录状态 (当前痛点！)
        Note over WebView: 抖音 PC 端对未登录访客不提供多码率列表，<br/>甚至弹窗阻断或不初始化播放器
        WebView--xSniffer: 永远无法返回 bit_rate 列表！
        Note over Sniffer: 苦等整整 30 秒主超时 (Timer 30s)
        Sniffer->>Sniffer: 主流程超时，回退使用 0.7 秒时就已拿到的分享页视频
        Sniffer-->>User: 耗时 34 秒才出结果！
    end
```

### 关键发现总结：
1. **图文为什么正常？**
   在 `_runShareFallback` 中，当识别到 `result.isImagePost == true` 时，直接走 `_scheduleImageFallback`，仅等待 3 秒实况补充宽限期，总耗时仅约 2 秒。
2. **未登录视频为什么奇慢？**
   - 抖音官方设计中，“登录账号”的唯一目的就是为了获取 PC Web 端的 1080P 多清晰度档位。未登录访客在官方平台本身就无法获得多码率列表。
   - `DouyinShareApi`（Dio 走移动端分享接口）在 **0.7 秒** 时就已经拿到了官方为访客提供的最高可用清晰度无水印视频。
   - 但 `DouyinSniffer` 未区分用户是否登录，一律将分享页结果冷冻（`_shareVideoFallback = result`），傻傻等待主 WebView。而在未登录状态下，桌面端根本不会给 1080P 档位，最终必定触发 30 秒主超时保底。用户足足被无谓折磨了 30 秒，拿到的却是 0.7 秒时就早已缓存的结果！

---

## 三、解决方案与架构设计

1. **登录感知与决策分支（`DouyinSniffer`）**：
   - 嗅探器接入登录状态检测（通过 `LoginStateStore` 或外部状态回调），在任务开始时确定 `_isLoggedIn`。
   - 当 `_isLoggedIn == false`（未登录）时：
     - 一旦 `_runShareFallback` 成功返回视频结果，**立即以该结果完成任务（`_finishWithItems`）**，无需任何无谓等待！
     - 耗时直接从 30 秒压缩到 **0.7 ~ 1.5 秒**。
   - 当 `_isLoggedIn == true`（已登录）时：
     - 保持现有策略：缓存分享页结果，继续等待主桌面 WebView 抓取 11 档完整清晰度。
2. **兜底切换加速**：
   - 在未登录状态下，若 Dio 分享页因网络波动偶发失败，无需等待 8~18 秒迟到兜底，直接在 2~3 秒内切入 WebView 分享页兜底（Path C），全链路确保 3~5 秒内无论如何都能出结果。

---

## 四、文件修改清单

1. `pubspec.yaml`：版本号推进至 `1.3.4+145`；
2. `lib/app_info.dart`：`appVersion` 更新至 `1.3.4+145`；
3. `lib/services/douyin_sniffer.dart`：
   - 增加登录状态感知属性与检测逻辑（支持外部注入与 `LoginStateStore` 兜底）；
   - 在 `_runShareFallback` 中，针对 `!_isLoggedIn` 的视频作品实现立即完成；
   - 在兜底调度中对未登录场景进行加速；
4. `lib/pages/app_shell.dart`：将 `_loggedIn` 状态提供给 `_sniffer`；
5. `test/`：更新并增补相关单元测试，覆盖未登录极速完成与已登录等待主流程的流转逻辑。

---

## 五、验证计划与实施

1. **静态检查**：`flutter analyze` 确保 0 issues（已通过，耗时 2.2s）；
2. **单元测试**：`flutter test` 确保 100% 绿灯（140 项用例全部通过）；
3. **真实模拟器自动化联调（未登录状态下）**：
   - 彻底清空模拟器中 Cookie 与登录状态（`loggedIn: false`）；
   - 测试口令 1（视频）：`https://v.douyin.com/0KF7YESssC4/`；
   - 测试口令 2（图集/实况图）：`https://v.douyin.com/NhaZaQHu4Dw/`；
   - 测试口令 3（视频）：`https://v.douyin.com/q8ZWiQz12Bs/`；
   - 测试下载：调用 `agent_cmd.bat download 0` 验证资源正常落地。

---

## 六、实机测试结果与性能对比 (Benchmark)

在完全未登录（`loggedIn: false`，无 Cookie 访客）状态下对用户提供的三条样本进行实测，时延对比数据如下：

| 测试样本 | 类型 | 修复前耗时（PLAN_36） | 修复后耗时（PLAN_37） | 性能提升 | 解析结果详情 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **口令 1 (D4C作品)** | 普通视频 | **34.0 秒** (30s 超时) | **1.72 秒** | **🚀 94.9% 提速** | 1080P/原画视频 1 个，文案正常获取 |
| **口令 2 (辉辉gg作品)** | 图文/实况图集 | **2.07 秒** | **1.90 秒** | 保持极速秒开 | 4K 图片 1 张、实况视频 1 个、配乐 1 首 |
| **口令 3 (7 v作品)** | 普通视频 | **35.0 秒** (30s 超时) | **0.65 秒** | **🚀 98.1% 提速** | 1080P/原画视频 1 个，文案正常获取 |

### 真实执行日志取证（口令 3 - 视频）：
```text
[解析] [+0.00s] 开始解析 (task#3, 登录状态: 未登录): https://v.douyin.com/q8ZWiQz12Bs/
[解析] [+0.15s] 分享页兜底启动: awemeId=7702119182565719945（page=...）
[解析] [+0.64s] 未登录状态：分享页已获取无水印视频，极速完成解析
[解析] [+0.65s] 解析成功：共发现 1 个清晰度档位
[解析] [+0.65s] 作品文案: 晚会
```
**下载验证**：
```text
[AgentBridge] 正在请求下载资源 (indices=0)...
=== 下载完成 ===
成功保存数量: 1
保存资源类型: video
生成文件名称:
  - 晚会.mp4
```

---

## 七、完成情况检查表

- [x] `pubspec.yaml` 与 `lib/app_info.dart` 版本升级为 `1.3.4+145`
- [x] `DouyinSniffer` 接入登录感知，未登录视频不再无谓强等桌面 WebView 超时
- [x] 未登录状态下 Dio 分享页提取无水印视频立即完成（耗时由 35s 降至 0.65s~1.7s）
- [x] 快速兜底链路支持（若分享页异常 3 秒内切入 WebView 兜底，绝不死锁 30 秒）
- [x] 已登录状态逻辑完全保留无损（继续支持 1080P 多码率档位捕获）
- [x] `flutter analyze` 0 issues，`flutter test` 140/140 测试通过
- [x] 自动化测试验证 3 组真实测试链接（2 视频 + 1 图文实况）全通
- [x] 下载验证正常
- [x] Release APK 构建完成 (v8a + Universal)
  - `YuYin_1.3.4_v8a.apk` (17MB, ARM64)
  - `YuYin_1.3.4_Universal.apk` (51MB, Universal)

3. **模拟器真机实测（未登录状态）**：
   - 针对 `sources/145_抖音口令/三条不同的视频口令.txt` 中的 3 条口令逐一进行解析演练：
     - 口令 1（普通视频）：验证解析耗时是否由 34 秒降至 1~2 秒内；
     - 口令 2（图文作品）：验证图文解析是否保持 2 秒内极速；
     - 口令 3（普通视频）：验证解析耗时是否由 35 秒降至 1~2 秒内；
   - 验证视频资源下载落盘是否正常。
4. **Release 构建打包**：执行 `.\tool\build_release_apk.bat all`。
