import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/common/save_memory_scope.dart';
import '../../models/media_item.dart';
import '../../models/save_page/author_works_selection.dart';
import '../../utils/download_settings_store.dart';
import '../../utils/save_page_debug_store.dart';
import '../../utils/save_selection_tree.dart';
import '../../utils/selection_mode_store.dart';
import 'save_page_common.dart';

part 'top/flow/top_author_selection_flow.dart';

part 'top/flow/top_quality_flow.dart';

part 'top/flow/top_selection_memory.dart';

part 'top/flow/top_sheet_action_flow.dart';

part 'top/debug/top_debug_snapshot.dart';

part 'top/widget/top_author_tile.dart';

part 'top/widget/top_avatar.dart';

/// 进入中层页面（单主页作品列表）的回调
typedef OnOpenAuthorCallback = FutureOr<AuthorWorksSelection?> Function(
  MultiHomeAuthorItem author,
  int index,
  List<SaveWorkItem> works,
  BatchVideoQualityMode qualityMode,
);

/// 三层结构保存页 — 顶层（多主页）预览与选择面板
///
/// 顶层始终位于主页解析流程：作者 -> 作品。作品的具体资源只有进入中层再打开底层后才会出现。
class MultiHomePreviewSheet extends StatefulWidget {
  const MultiHomePreviewSheet({
    super.key,
    required this.authors,
    this.headers = const {},
    this.useMemoryDefault = true,
    this.initialQualityMode,
    this.initialWorksBySecUid = const {},
    this.memoryScope = SaveMemoryScope.homeTop,
    this.onOpenAuthor,
    this.onQualityChanged,
  });

  final List<MultiHomeAuthorItem> authors;
  final Map<String, String> headers;
  final bool useMemoryDefault;
  final BatchVideoQualityMode? initialQualityMode;

  /// 解析页预加载或上次进入中层后的作者作品树
  final Map<String, List<SaveWorkItem>> initialWorksBySecUid;

  /// 顶层记忆作用域（主页流程固定 homeTop）
  final SaveMemoryScope memoryScope;

  final OnOpenAuthorCallback? onOpenAuthor;
  final ValueChanged<BatchVideoQualityMode>? onQualityChanged;

  static Future<MultiHomeSelectionResult?> show(
    BuildContext context, {
    required List<MultiHomeAuthorItem> authors,
    Map<String, String> headers = const {},
    bool useMemoryDefault = true,
    BatchVideoQualityMode? initialQualityMode,
    Map<String, List<SaveWorkItem>> initialWorksBySecUid = const {},
    SaveMemoryScope memoryScope = SaveMemoryScope.homeTop,
    OnOpenAuthorCallback? onOpenAuthor,
    ValueChanged<BatchVideoQualityMode>? onQualityChanged,
  }) {
    return showModalBottomSheet<MultiHomeSelectionResult>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => MultiHomePreviewSheet(
        authors: authors,
        headers: headers,
        useMemoryDefault: useMemoryDefault,
        initialQualityMode: initialQualityMode,
        initialWorksBySecUid: initialWorksBySecUid,
        memoryScope: memoryScope,
        onOpenAuthor: onOpenAuthor,
        onQualityChanged: onQualityChanged,
      ),
    );
  }

  @override
  State<MultiHomePreviewSheet> createState() => _MultiHomePreviewSheetState();
}

class _MultiHomePreviewSheetState extends State<MultiHomePreviewSheet> {
  late List<MultiHomeAuthorItem> _authors;
  late Map<String, List<SaveWorkItem>> _worksBySecUid;
  late BatchVideoQualityMode _qualityMode;
  bool _hasRecordedSelection = false;
  int? _openingIndex;

  @override
  void initState() {
    super.initState();
    _worksBySecUid = {
      for (final entry in widget.initialWorksBySecUid.entries)
        entry.key: List<SaveWorkItem>.from(entry.value),
    };

    final rememberedQuality =
        widget.initialQualityMode ??
        DownloadSettingsStore.getBatchQuality(widget.memoryScope);
    // 新解析的主页作品默认 highest，需要先用 homeTop 记忆覆盖未显式选择的视频作品
    if (widget.initialQualityMode == null) {
      for (final entry in _worksBySecUid.entries) {
        _worksBySecUid[entry.key] = [
          for (final work in entry.value)
            work.isVideo &&
                    work.qualityChoice.level != WorkVideoQualityLevel.specific
                ? work.copyWith(
                    qualityChoice:
                        rememberedQuality == BatchVideoQualityMode.lowest
                        ? const WorkVideoQualityChoice.lowest()
                        : const WorkVideoQualityChoice.highest(),
                  )
                : work,
        ];
      }
    }

    final defaultMode = SelectionModeStore.getHomeTopSelectAllMode();
    final defaultState = defaultMode == 2
        ? AuthorSelectionState.none
        : AuthorSelectionState.all;

    _authors = widget.authors.map((author) {
      final copy = widget.useMemoryDefault
          ? author.copyWith(selectionState: defaultState)
          : author;
      if (widget.useMemoryDefault) {
        final secUid = copy.profile.secUid.trim();
        final works = _worksOf(secUid);
        if (works.isNotEmpty) {
          _worksBySecUid[secUid] =
              SaveSelectionTree.applyAuthorSelection(works, defaultState);
        }
      }
      return copy;
    }).toList();

    this._refreshAuthorStates();
    _qualityMode =
        widget.initialQualityMode ?? this._aggregateAll() ?? rememberedQuality;
    this._publishDebugState();
  }

  @override
  void dispose() {
    this._recordSelectionMode();
    super.dispose();
  }

  /// 供流程分片调用的状态刷新入口
  void _refresh(VoidCallback fn) => setState(fn);

  List<SaveWorkItem> _worksOf(String secUid) =>
      _worksBySecUid[secUid] ?? const [];

  List<SaveWorkItem> get _allWorks => [
    for (final author in _authors) ..._worksOf(author.profile.secUid),
  ];

  bool get _hasAuthors => _authors.isNotEmpty;

  bool get _isAllSelected =>
      _hasAuthors &&
      _authors.every((author) => author.selectionState == AuthorSelectionState.all);

  int get _selectedCount => _authors
      .where((author) => author.selectionState != AuthorSelectionState.none)
      .length;

  /// 上层控制下层：作者全选/全不选，递归设置其全部作品。
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 $_selectedCount / ${_authors.length} 位作者',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SaveQualityToggleChip(
                    key: const ValueKey('quality_toggle_btn'),
                    mode: _qualityMode,
                    onTap: this._toggleQualityMode,
                  ),
                  const SizedBox(width: 6),
                  SaveCategoryFilterButton(
                    key: const ValueKey('home_select_all_btn'),
                    label: '全选',
                    hasItems: _hasAuthors,
                    isSelected: _isAllSelected,
                    onTap: this._toggleSelectAll,
                  ),
                ],
              ),
            ),
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                    ),
                itemCount: _authors.length,
                itemBuilder: (context, index) => this._buildAuthorTile(index),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('multi_home_confirm_btn'),
                  onPressed: _selectedCount == 0 ? null : this._confirm,
                  icon: const Icon(Icons.save_alt),
                  label: Text('保存选中项 ($_selectedCount)'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ignore_for_file: unnecessary_this
