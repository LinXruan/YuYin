# PLAN_28：下载资源自动智能命名体系构建（作品标题/文案捕获、字数上限截断与同类资源序号后缀）

## 一、需求背景与目标

目前应用在下载资源时，统一采用时间戳作为文件名前缀（形如 `YuYin_1711234567890_1.mp4`、`YuYin_1711234567890_1.jpg`）。
这种方式虽然避免了命名冲突，但用户在相册或文件管理器中查阅时，无法直接从文件名识别资源对应的抖音作品内容，辨识度低且难以整理。

本次需求旨在构建**抖音作品标题与文案的智能捕获与自适应命名机制**，使保存到本地的文件具备人类可读的语义化名称，并兼顾操作系统文件名合法性与多资源命名区分规则。

### 1. 核心需求点
1. **作品标题（Title）优先捕获**：
   - 深入捕获流程，从主 WebView 注入脚本、iesdouyin 分享页 API、播放器配置等源头解析作品的标题（`item_title` / `title`）；
2. **文案（Desc）优雅兜底捕获**：
   - 针对绝大多数没有独立标题的抖音作品，无缝回退提取作品文案描述（`desc` / `share_title`）；
   - 若标题与文案均为空，安全回退到时间戳前缀保底，确保写入永远成功。
3. **文件名清洗与字数截断（10 中文字符上限）**：
   - 过滤操作系统与存储系统保留的非法字符（`\ / : * ? " < > |`、换行符、控制字符等）；
   - 设定字数引用上限：按 **10 个中文字符**（等价 20 个 ASCII 字符宽度）为预算基准；
   - 超出上限部分截断并紧跟省略号 `...`（例如："今天去吃火锅特别开心真的绝了" -> "今天去吃火锅特别开心..."）。
4. **同类资源自适应序列后缀（`_1`, `_2`, `_3`...）**：
   - **单次下载多个同类资源**（例如下载包含 5 张图片的图集）：
     赋予同类序号后缀，如 `标题..._1.jpg`、`标题..._2.jpg`、`标题..._3.jpg`；
   - **单次下载单个或多种不同类资源**（例如实况图下载包含 1 张图片 + 1 个视频 + 预留 1 个音频）：
     因为每种类型的同类资源仅有 1 个，**严格不加额外序号后缀**！输出 `标题....jpg`、`标题....mp4`、`标题....mp3`；
   - **单次下载多个多种资源**（例如勾选了 3 个实况图，共 3 张图 + 3 个视频）：
     图片为 `标题..._1.jpg` ~ `标题..._3.jpg`，视频为 `标题..._1.mp4` ~ `标题..._3.mp4`。
5. **版本号升级**：
   - 版本升级至 `1.2.7`，构建号升级至 `137`。

---

## 二、架构设计与核心技术方案

```mermaid
flowchart TD
    subgraph Capture["1. 标题与文案捕获层 (Capture Layer)"]
        SrcA["源A: 主WebView JS注入<br/>(node.item_title / node.desc / player / DOM)"]
        SrcB["源B: iesdouyin 分享页 API<br/>(item.item_title / item.desc / share_info)"]
        SrcC["源C: 分享页移动端 WebView 兜底<br/>(RouterData & DOM)"]
        SrcD["源D: 用户粘贴口令兜底<br/>(UrlParser 提取文本)"]
    end

    subgraph Data["2. 数据载体与流转层 (Model & Sniffer Layer)"]
        ShareRes["DouyinShareResult<br/>title / desc"]
        SniffRes["SniffResult<br/>title / desc"]
        ParsePg["ParsePage 控制器<br/>计算最终 baseTitle"]
    end

    subgraph Naming["3. 命名与清洗算法层 (Naming & Formatting Layer)"]
        Sanitize["文件名非法字符过滤<br/>剔除 / \\ : * ? \" < > | 及换行控制符"]
        Truncate["智能长度截断<br/><= 10 中文字符 (或 20 字符宽度)<br/>超出追加 '...'"]
        Classifier["同类资源计数与分类器<br/>items.where(type == currentType).length"]
        SuffixGen{"同类资源数 > 1 ?"}
        WithSuffix["附加同类序号: _1, _2..."]
        NoSuffix["不加序号后缀: 直接命名"]
    end

    subgraph Save["4. 原生存储写入 (Storage Layer)"]
        MediaSaverNative["MainActivity (MediaStore / SAF)<br/>生成目标文件"]
    end

    SrcA --> SniffRes
    SrcB --> ShareRes
    SrcC --> SniffRes
    ShareRes --> SniffRes
    SniffRes --> ParsePg
    SrcD -.-> ParsePg

    ParsePg --> Sanitize
    Sanitize --> Truncate
    Truncate --> Classifier
    Classifier --> SuffixGen
    SuffixGen -- 是 --> WithSuffix
    SuffixGen -- 否 --> NoSuffix

    WithSuffix --> MediaSaverNative
    NoSuffix --> MediaSaverNative
```

### 1. 标题与文案的优先捕获链
- **第一优先级（标题）**：
  检查作品节点的 `item_title` 或 `title`。若存在且不全为空白字符，作为首选标题。
- **第二优先级（文案）**：
  若无独立标题，提取作品节点的 `desc`（文案描述，即作者发布的文字内容）。
- **第三优先级（DOM / 页面元数据）**：
  若为播放器兜底或单视频流，通过 JS 捕获 `meta[property="og:title"]`、`h1` 或清洗后的 `document.title`。
- **第四优先级（剪贴板口令文本）**：
  若网络层均无元数据，从用户输入的分享文本中剔除 URL 与系统提示词后提取文本。
- **保底策略（时间戳）**：
  若上述皆不可用，回退至 `YuYin_${timestamp}`，确保文件名唯一且永远不报错。

### 2. 文本清洗与 10 中文字符截断规则
- **非法字符过滤**：
  使用正则 `[\/\\:*?"<>|\r\n\t]` 替换为空格，合并连续空格并 `trim()`；
- **字符宽度权重计算**：
  - CJK 汉字、全角符号、Emoji：权重计为 `1.0`（或 2 字节显示宽度）；
  - ASCII 字母、数字、英文半角标点：权重计为 `0.5`（或 1 字节显示宽度）；
  - 上限阈值设为 `10.0`（相当于 10 个中文字符或 20 个英文字符）；
  - 若总权重超过 `10.0`，在不超过阈值的位置截断，并紧随追加 `...`。

### 3. 同类资源后缀派发算法
在 `VideoDownloader.downloadItems` 中，遍历选中的 `items`：
```dart
final typeTotal = items.where((it) => it.type == item.type).length;
final typeIndex = items.take(i + 1).where((it) => it.type == item.type).length;

final suffix = typeTotal > 1 ? '_$typeIndex' : '';
final fileName = '$cleanBaseName$suffix.$ext';
```
- **纯视频（1 个）**：`typeTotal = 1` -> 无后缀 -> `美食探店....mp4`
- **图集（4 张图）**：`typeTotal = 4` -> 有后缀 -> `美食探店..._1.jpg`, `美食探店..._2.jpg`, ...
- **单套实况图（1 图 + 1 视频）**：
  - 图：`typeTotal = 1` -> 无后缀 -> `美食探店....jpg`
  - 视：`typeTotal = 1` -> 无后缀 -> `美食探店....mp4`
  - 完美符合“单个多种资源不加后缀”的指示要求！

---

## 三、待修改与新增文件清单

1. **`lib/utils/file_name_formatter.dart`** [新增]：
   - 负责标题/文案清洗、中文字符等价权重计算、10 汉字截断（超长加 `...`）；
   - 负责根据 `items` 列表与当前 `item` 派发同类资源 `_1` 后缀或无后缀。
2. **`lib/models/media_item.dart`** [修改]：
   - `SniffResult` 增加 `title` 与 `desc` 字段。
3. **`lib/services/douyin_share_api.dart`** [修改]：
   - `DouyinShareResult` 增加 `title` 与 `desc` 字段；
   - `parseItem` 解析并提取 `title` 与 `desc`。
4. **`lib/services/js_script_builder.dart`** [修改]：
   - JS 捕获脚本中的 `scanTree`、`scanPlayerData`、`reportSingle` 提取 `item_title`、`title`、`desc`、DOM 元数据并挂载到回传的 `result` 消息中。
5. **`lib/services/douyin_sniffer.dart`** [修改]：
   - 接收 JS 回传的 `title` 与 `desc`，传递至 `SniffResult`；分享页兜底同理。
6. **`lib/services/video_downloader.dart`** [修改]：
   - `downloadItems` 接收 `String? baseTitle`，调用 `FileNameFormatter` 生成标准化文件名。
7. **`lib/pages/parse_page.dart`** [修改]：
   - 解析成功后提取 `result.title ?? result.desc`，调用下载器保存。
8. **`lib/app_info.dart` 与 `pubspec.yaml`** [修改]：
   - 升级版本至 `1.2.7+137`。
9. **`test/file_name_formatter_test.dart`** [新增]：
   - 针对非法字符过滤、10 中文字符截断规则、同类多资源与单套多类型资源的命名单元测试。

---

## 四、验证计划

1. **自动化单元测试**：
   - 运行 `flutter test`，确保原有 98 项测试全部通过，且新增的命名规则单元测试 100% 覆盖并绿灯通过。
2. **静态代码分析**：
   - 运行 `flutter analyze`，确保 0 error, 0 warning。
3. **真机与批处理打包测试**：
   - 运行 `tool\build_release_apk.bat v8a`，生成 `YuYin_1.2.7_v8a.apk`；
   - 验证真机实际下载视频、多图、实况图的落盘文件名是否严格符合规范。

