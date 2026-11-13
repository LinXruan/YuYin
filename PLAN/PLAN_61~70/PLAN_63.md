# PLAN_63：三层选择树（重写版） (版本 1.5.5+177)

## 一、重新理解：这就是一棵选择树

保存页不是三个各管各的列表，而是一棵父子选择树：

- 主页解析：顶层作者 -> 中层作品；一开始只有两层，因为主页只解析出作品链接，没有具体资源。中层点击作品封面的「打开」进入底层后，才临时形成第三层。
- 多作品解析：中层作品 -> 底层资源；始终只有两层，没有顶层。
- 单作品解析：只有底层资源；一开始就是一层。

树的核心规则只有两条：

1. **上层控制下层**：勾选/取消作者，等于勾选/取消其下所有作品；勾选/取消作品，等于勾选/取消其下所有资源。
2. **下层控制上层**：部分作品被选中，作者显示部分选择（虚线）；部分资源被选中，作品显示部分选择（虚线）；画质同理，下层出现特定档位后，上层聚合为混合画质。

所有虚线框、混合画质、保存内容，都必须由这棵树派生，不能各页面自己维护一套状态。

---

## 二、上一版失败点与回滚范围

### 2.1 保留

保留 PLAN_62 已完成的落盘、历史、SAF、文件命名、日志修复、调试接口，不回滚这些。

### 2.2 需要替换的错误实现

1. 顶层作者点击/全选只修改作者状态，没有递归修改作品列表。
   - 位置：top_multi_home_sheet.dart 的 _toggleAuthor、_toggleSelectAll。
   - 处理：改为调用统一的树操作函数，递归设置该作者/全部作者的 works。
2. 顶层画质只读取全局 DownloadSettingsStore，不读取作品树的画质聚合。
   - 位置：top_multi_home_sheet.dart 的 _qualityMode、_handleOpenAuthor。
   - 处理：每次子层返回后重新聚合；没有作品时才回退到当前上下文记忆。
3. 顶层保存读取 ParsePage._authorWorksCache 旁路缓存，而不是顶层页面返回的选择树。
   - 位置：parse_page.dart 的 _parseUserHomes + user_home_batch_saver.dart。
   - 处理：顶层确认时返回 worksBySecUid；保存只使用返回值。
4. 中层作品点击/分类全选只修改作品 selectionState，没有同步资源选择。
   - 位置：middle_multi_work_sheet.dart 的 _toggleWork、_toggleCategory。
   - 处理：作品设为全选时清空 selectedResources（空表示全选）；设为未选时清空资源；部分状态只由底层返回产生。
5. 中层画质切换只改 qualityChoice，没有清除视频 selectedResources。
   - 位置：middle_multi_work_sheet.dart 的 _toggleQualityMode。
   - 处理：切换最高/最低时清空所有视频作品的 selectedResources，避免保存继续使用旧档位。
6. 全局筛选/画质记忆混用。
   - 位置：selection_mode_store.dart、download_settings_store.dart。
   - 处理：按「解析来源 + 层级」拆分独立作用域，旧数据一次性迁移。
7. 主页作品没有 parsedResult 时，不能假设资源列表存在。
   - 处理：中层打开底层时按需解析；树操作在资源未知时只维护作品级 all/none；保存时由 WorkBatchSaver 补解析。

前置日志修复保留：主页批量保存时，作者名只在作者级日志出现一次，进度行不再重复输出作者名。

---

## 三、选择树模型

### 3.1 节点与状态

- 顶层节点：作者（MultiHomeAuthorItem）
- 中层节点：作品（SaveWorkItem）
- 底层节点：资源（MediaItem）

状态：

    AuthorSelectionState { none, partial, all }
    WorkSelectionState { none, partial, all }

作品状态派生：

    deriveWorkState(work, parsedItems):
      - selectedResources 为空且 selectionState == all -> all
      - selectedResources 为空且 selectionState == none -> none
      - parsedItems 可用时按 selectedResources 数量比较：
          0 -> none；全部 -> all；其余 -> partial
      - parsedItems 不可用且 selectedResources 非空 -> 保持当前 state

作者状态派生：

    deriveAuthorState(works):
      - 全部作品 all -> all
      - 全部作品 none -> none
      - 其余（含 partial）-> partial

### 3.2 新增纯函数工具 save_selection_tree.dart

新增 lib/utils/save_selection_tree.dart，所有树操作集中在这里，页面只调用：

    applyAuthorSelection(List<SaveWorkItem> works, AuthorSelectionState state)
      - all：每个作品 selectionState=all，selectedResources=[]，视频 qualityChoice 保持当前值
      - none：每个作品 selectionState=none，selectedResources=[]
      - partial 不允许直接写入（只能由下层派生）

    applyWorkSelection(SaveWorkItem work, WorkSelectionState state)
      - all：selectionState=all，selectedResources=[]
      - none：selectionState=none，selectedResources=[]
      - partial 不允许直接写入（只能由底层返回）

    applyWorkSelectionToCategory(
      List<SaveWorkItem> works,
      WorkMediaKind kind,
      WorkSelectionState state,
    )

    applyBottomSelection(
      SaveWorkItem work,
      List<MediaItem> parsedItems,
      List<MediaItem> selectedResources,
    )
      - 根据 parsedItems 与 selectedResources 派生 all/partial/none
      - 写回 selectedResources、selectionState、parsedResult

    applyQualityToAuthorWorks(List<SaveWorkItem> works, BatchVideoQualityMode mode)
      - 只处理视频作品
      - mode highest/lowest：写入 qualityChoice，清空视频 selectedResources
      - mode mixed：不批量改作品，只作为显示聚合结果

    applyQualityToCategory(
      List<SaveWorkItem> works,
      WorkMediaKind kind,
      BatchVideoQualityMode mode,
    )

    aggregateQuality(List<SaveWorkItem> works):
      - 忽略非视频作品
      - 无视频 -> null
      - 全部 highest -> highest
      - 全部 lowest -> lowest
      - 其余（含 specific/mixed）-> mixed

### 3.3 画质优先级

单个视频作品保存时：

    resolveWorkQuality(work, batchMode):
      1. selectedResources 中有视频 -> 使用该视频档位
      2. work.qualityChoice == specific -> 使用该档位
      3. batchMode == mixed -> 使用 work.qualityChoice
      4. batchMode == lowest -> lowest
      5. 否则 highest

注意：顶层/中层切换最高/最低时会清空视频 selectedResources，所以第 1 条不会覆盖用户刚切换的批量画质。

### 3.4 两种初始树形

- 主页：顶层作者 + 中层作品。作品 parsedResult 可能为 null，selectedResources 为空；此时作品只有 all/none 两态。
- 多作品：中层作品 + 底层资源。作品 parsedResult 已缓存；底层可随时打开。
- 单作品：只有底层资源。

主页作品只有在打开底层并确认后，才会出现 partial 状态；在此之前，作者状态只可能是 all/none。

---

## 四、UI 行为规格

### 4.1 顶层

- 点击作者缩略图：all <-> none，递归设置该作者所有作品。
- 点击「全选」：全部作者 all <-> none，递归设置所有作品。
- 作者缩略图 partial：deriveAuthorState(works)==partial，显示虚线。
- 顶层画质标签：
  - 初始值取 homeTop 作用域记忆；
  - 进入中层返回后，aggregateQuality(该作者全部视频作品)；
  - 顶层确认前，对全部作者作品再聚合一次；
  - 点击切换 highest <-> lowest，递归设置所有作者的全部视频作品，并清空视频 selectedResources；
  - 显示 mixed 时点击 -> highest。

### 4.2 中层

- 点击作品缩略图：all <-> none，递归设置该作品资源（selectedResources 清空表示全选）。
- 点击「视频」「图文」分类：该分类全部作品 all <-> none。
- 作品缩略图 partial：由底层返回的 selectedResources 派生，显示虚线。
- 中层画质标签：
  - 初始值取 homeMiddle / multiMiddle 作用域记忆；
  - 底层返回后，aggregateQuality(全部视频作品)；
  - 点击切换 highest <-> lowest，递归设置全部视频作品，并清空视频 selectedResources；
  - 显示 mixed 时点击 -> highest。

### 4.3 底层

- 资源勾选/取消：维护 selectedResources。
- 确认/返回：返回 WorkDetailSelection(selectedResources, qualityChoice, parsedResult, state)。
- 视频画质：点选具体档位，qualityChoice=specific；返回中层后触发 mixed。
- 根层保存按钮保存选中资源；嵌套层按钮返回中层。

---

## 五、记忆隔离

新增 SaveMemoryScope：

    enum SaveMemoryScope {
      homeTop,
      homeMiddle,
      homeBottom,
      multiMiddle,
      multiBottom,
      singleBottom,
    }

| 作用域 | 使用位置 | 记忆 |
| --- | --- | --- |
| homeTop | 顶层 | 作者全选 a/b、顶层画质 |
| homeMiddle | 主页来源中层 | 视频/图文 a/b、中层画质 |
| homeBottom | 主页来源底层 | 图片/实况/音频 a/b |
| multiMiddle | 多作品中层 | 视频/图文 a/b、中层画质 |
| multiBottom | 多作品底层 | 图片/实况/音频 a/b |
| singleBottom | 单作品底层 | 图片/实况/音频 a/b |

### 5.1 SelectionModeStore

- 把图片/视频/音频、视频/图文、作者全选全部改为按 scope 存储。
- 旧 JSON 迁移：
  - 旧 image/video/audio -> 同时复制到 homeBottom、multiBottom、singleBottom；
  - 旧 work_video/work_image -> 同时复制到 homeMiddle、multiMiddle；
  - 旧 home_all -> homeTop；
  - 迁移完成后各 scope 独立写入。
- API 使用 scope 参数；页面不允许再调用无 scope 的旧方法。

### 5.2 DownloadSettingsStore

- 批量画质从单一值改为 Map<SaveMemoryScope, BatchVideoQualityMode>，只使用 homeTop/homeMiddle/multiMiddle。
- 旧 batchVideoQualityMode 迁移到三个 scope。
- mixed 不持久化；只有 highest/lowest 写入记忆。
- 保留旧 getter/setter 映射到 multiMiddle 作为兼容，但页面改用 scope API。

---

## 六、保存数据流

### 6.1 主页

    ParsePage._parseUserHomes
      -> MultiHomePreviewSheet(authors, initialWorksBySecUid)
      -> 顶层确认
           selectedAuthors
           worksBySecUid（所有作者的最新作品树）
           qualityMode
      -> UserHomeBatchSaver.saveAuthors(
           authors: selectedAuthors,
           worksBySecUid: 返回值,
           qualityMode: 返回值,
         )
      -> 作者 all：保存全部作品
         作者 partial：保存 state.isSelected 的作品
         作者 none：跳过
      -> WorkBatchSaver 内部再按 selectedResources / qualityChoice 保存

### 6.2 多作品

    ParsePage._parseMultiWorks
      -> MiddleMultiWorkSheet(nested:false, scope: multiMiddle)
      -> 确认返回 selectedWorks + allWorks + qualityMode
      -> WorkBatchSaver.saveWorks(selectedWorks, qualityMode)

### 6.3 单作品

    ParsePage 单作品
      -> ImagePreviewSheet/VideoQualitySheet(scope: singleBottom)
      -> 保存 selectedResources

### 6.4 顶层不再读旁路缓存

- MultiHomePreviewSheet 增加 worksBySecUid 参数，内部维护一份；
- 每次中层返回后更新；
- 确认时通过 MultiHomeSelectionResult 返回；
- ParsePage 保存只使用返回值；
- _authorWorksCache 只作为顶层初始数据来源，不再作为保存数据源。

---

## 七、主页无预缓存资源的处理

- _buildHomeWorks 生成的 SaveWorkItem.parsedResult == null。
- 中层打开作品底层时：
  - 调用 sniffVideoUrl 解析；
  - 成功后回填 parsedResult、coverUrl、title；
  - 失败则记录日志并保持原状。
- 树操作在 parsedResult 未知时：
  - 作品 all/none 只改 selectionState 与 selectedResources；
  - 不尝试比较资源数量；
  - 不聚合该作品的 specific 画质。
- 顶层保存时 WorkBatchSaver 对 parsedResult 为空的作品补解析。

---

## 八、任务分解

0. [ ] **回滚/替换错误选择逻辑**：
   - 保留落盘、历史、SAF、日志修复、调试接口；
   - 替换 top_multi_home_sheet 的作者级独立状态逻辑；
   - 替换 middle_multi_work_sheet 的作品级独立状态逻辑；
   - 替换 parse_page 的旁路 cache 保存逻辑；
   - 替换 selection_mode_store/download_settings_store 的全局记忆键。
1. [ ] **先写失败测试**：
   - 顶层勾选作者 -> 作品全选/全不选；
   - 中层勾选作品 -> 资源全选/全不选；
   - 底层部分资源 -> 中层虚线 -> 顶层虚线；
   - 底层 specific -> 中层 mixed -> 顶层 mixed；
   - 顶层切换画质 -> 保存不再使用旧 selectedResources；
   - 记忆隔离。
   先让这些测试在旧代码上失败，再改实现。
2. [ ] **新增 save_selection_tree.dart 与单元测试**。
3. [ ] **顶层改造**：递归选择、虚线、画质聚合、worksBySecUid 返回。
4. [ ] **中层改造**：递归选择、资源同步、虚线、画质聚合、清空视频 selectedResources。
5. [ ] **底层改造**：scope 参数、返回 selectedResources/qualityChoice/parsedResult。
6. [ ] **解析页接线**：三种流程分别传 scope；保存只用返回值。
7. [ ] **记忆存储重构**：SelectionModeStore/DownloadSettingsStore scope 化 + 迁移。
8. [ ] **日志回归**：作者名每作者只出现一次。
9. [ ] **质量门禁**：analyze 0，test 全绿。
10. [ ] **模拟器联调**：三种流程的上下控制、虚线、mixed、保存内容、记忆隔离。
11. [ ] **版本 1.5.5+177 与 Release 构建**。

---

## 九、验收标准

- 顶层点击作者：该作者所有作品同步全选/全不选；保存内容随之一致。
- 顶层点击全选：所有作者及作品同步全选/全不选。
- 中层点击作品：该作品所有资源同步全选/全不选；保存内容随之一致。
- 中层点击视频/图文分类：该分类所有作品同步全选/全不选。
- 底层只选部分资源：返回中层后作品虚线；返回顶层后作者虚线。
- 底层选视频 specific：中层显示混合画质；返回顶层后顶层显示混合画质；保存按该档位。
- 顶层/中层切换最高/最低：保存使用新档位，不被旧 selectedResources 覆盖。
- 主页解析只解析出作品链接时：顶层/中层两层正常工作；打开作品后才出现底层与 partial 状态。
- 多作品解析：中层/底层两层正常工作。
- 单作品解析：底层正常工作。
- 三种来源的筛选/画质记忆互不串扰。
- 日志作者名不重复刷屏。
- flutter analyze 0 issues；flutter test 全绿；Release APK 构建成功。

---

## 十、风险

1. 主页作品 parsedResult 为空时，资源级状态未知；必须先解析再判断 partial，不能凭 empty 列表猜测。
2. 顶层/中层批量画质切换必须清空视频 selectedResources，否则保存优先级会使用旧档位。
3. 记忆迁移要复制旧值到多个新 scope，迁移后立即独立；不能继续共用。
4. 顶层保存必须使用返回的 worksBySecUid，禁止继续读 _authorWorksCache。
5. 底层 nested 与根层使用不同 scope，不能复用同一组筛选记忆。

---

## 十一、执行结果（2026-11-13）

- 版本：1.5.5+177。
- flutter analyze：0 issues。
- flutter test：319/319 全部通过。
- 模拟器联调（有界面模拟器，REST + uiautomator）：
  - 主页解析 14 个作品；顶层全选后进入中层显示 14/14；取消 1 个作品后中层显示 13/14，返回顶层作者显示「部分选择」虚线。
  - 在中层打开视频作品，选择中间档位 720P 后返回：中层作品显示「部分选择」虚线，画质标签显示「混合画质」；返回顶层后作者仍为部分选择，顶层画质显示「混合画质」。
  - 顶层保存日志确认「作者【琳玄染】开始保存（13 个作品）」，说明中层排除的 1 个作品没有进入顶层保存。
  - 多作品解析进入中层，打开视频选择 540P 后返回：中层显示部分选择与混合画质；保存成功 1/1，落盘文件 1,859,294 字节，与 540P 档位体积一致。
  - 日志验证：作者名仅在「作者【琳玄染】开始保存（13 个作品）」出现一次，进度行为「正在准备 1/13」「正在保存 1/13：1/1」，不再重复作者名。
  - 记忆隔离、顶层递归选择、底层 specific 聚合 mixed 等由 plan_63_test 的纯函数与 Widget 测试覆盖。
  - 首次截图复测发现顶层→中层同步失败：顶层点作者/画质后，中层仍使用旧作品树。已修复：顶层回调携带最新 works + qualityMode，ParsePage 进入中层时不再读旧缓存，并禁止中层记忆覆盖顶层选择。
  - 修复后通过 GET /api/save-debug 复测：顶层作者 none->all 后进入中层 14/14 全选；顶层切最低后进入中层 quality=lowest、视频作品 quality=lowest；中层全选进入底层 4/4，中层未选进入底层 0/4。
- 新增调试接口：GET /api/save-debug；CLI：.\tool\agent_cmd.bat save-debug；已写入 DEBUG.md。
- Release 构建：YuYin_1.5.5_v8a.apk 18 MB、YuYin_1.5.5_Universal.apk 53 MB；v8a 校验 versionCode=177、versionName=1.5.5。
