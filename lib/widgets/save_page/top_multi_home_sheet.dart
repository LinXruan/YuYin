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

    _refreshAuthorStates();
    _qualityMode =
        widget.initialQualityMode ?? _aggregateAll() ?? rememberedQuality;
    _publishDebugState();
  }

  @override
  void dispose() {
    _recordSelectionMode();
    super.dispose();
  }

  List<SaveWorkItem> _worksOf(String secUid) =>
      _worksBySecUid[secUid] ?? const [];

  List<SaveWorkItem> get _allWorks => [
    for (final author in _authors) ..._worksOf(author.profile.secUid),
  ];

  BatchVideoQualityMode? _aggregateAll() =>
      SaveSelectionTree.aggregateQuality(_allWorks);

  void _refreshAuthorStates() {
    _authors = [
      for (final author in _authors)
        _worksOf(author.profile.secUid).isEmpty
            ? author
            : author.copyWith(
                selectionState: SaveSelectionTree.deriveAuthorState(
                  _worksOf(author.profile.secUid),
                ),
              ),
    ];
  }

  void _recordSelectionMode() {
    if (_hasRecordedSelection) return;
    _hasRecordedSelection = true;
    SelectionModeStore.updateFromHomeSelections(
      _authors.map((author) => author.selectionState).toList(),
    );
    unawaited(
      DownloadSettingsStore.recordBatchQualitySelection(
        widget.memoryScope,
        _qualityMode,
      ),
    );
  }

  bool get _hasAuthors => _authors.isNotEmpty;

  bool get _isAllSelected =>
      _hasAuthors &&
      _authors.every((author) => author.selectionState == AuthorSelectionState.all);

  int get _selectedCount => _authors
      .where((author) => author.selectionState != AuthorSelectionState.none)
      .length;

  /// 上层控制下层：作者全选/全不选，递归设置其全部作品。
  void _toggleAuthor(int index) {
    final author = _authors[index];
    final secUid = author.profile.secUid.trim();
    final next = author.selectionState == AuthorSelectionState.all
        ? AuthorSelectionState.none
        : AuthorSelectionState.all;
    setState(() {
      final works = _worksOf(secUid);
      if (works.isNotEmpty) {
        _worksBySecUid[secUid] =
            SaveSelectionTree.applyAuthorSelection(works, next);
      }
      _authors[index] = author.copyWith(selectionState: next);
      _refreshAuthorStates();
      _qualityMode = _aggregateAll() ?? _qualityMode;
    });
    _publishDebugState();
  }

  /// 上层控制下层：全部作者全选/全不选，递归设置所有作品。
  void _toggleSelectAll() {
    if (!_hasAuthors) return;
    final target = _isAllSelected
        ? AuthorSelectionState.none
        : AuthorSelectionState.all;
    setState(() {
      for (var i = 0; i < _authors.length; i++) {
        final secUid = _authors[i].profile.secUid.trim();
        final works = _worksOf(secUid);
        if (works.isNotEmpty) {
          _worksBySecUid[secUid] =
              SaveSelectionTree.applyAuthorSelection(works, target);
        }
        _authors[i] = _authors[i].copyWith(selectionState: target);
      }
      _refreshAuthorStates();
      _qualityMode = _aggregateAll() ?? _qualityMode;
    });
    _publishDebugState();
  }

  /// 上层控制下层：顶层画质切换递归应用到所有作者的全部视频作品。
  void _toggleQualityMode() {
    final next = _qualityMode == BatchVideoQualityMode.highest
        ? BatchVideoQualityMode.lowest
        : BatchVideoQualityMode.highest;
    setState(() {
      for (final author in _authors) {
        final secUid = author.profile.secUid.trim();
        final works = _worksOf(secUid);
        if (works.isEmpty) continue;
        _worksBySecUid[secUid] =
            SaveSelectionTree.applyQualityToWorks(works, next);
      }
      _qualityMode = next;
    });
    unawaited(
      DownloadSettingsStore.setBatchQuality(widget.memoryScope, next),
    );
    widget.onQualityChanged?.call(next);
    _publishDebugState();
  }

  Future<void> _handleOpenAuthor(int index) async {
    final callback = widget.onOpenAuthor;
    if (callback == null || _openingIndex != null) return;
    setState(() => _openingIndex = index);
    try {
      final secUid = _authors[index].profile.secUid.trim();
      final updated = await callback(
        _authors[index],
        index,
        List<SaveWorkItem>.from(_worksOf(secUid)),
        _qualityMode,
      );
      if (!mounted || updated == null) return;
      setState(() {
        _worksBySecUid[secUid] = List<SaveWorkItem>.from(updated.works);
        _authors[index] = _authors[index].copyWith(
          selectionState: SaveSelectionTree.deriveAuthorState(updated.works),
        );
        _qualityMode = _aggregateAll() ?? updated.qualityMode;
      });
      _publishDebugState();
    } finally {
      if (mounted) setState(() => _openingIndex = null);
    }
  }

  void _confirm() {
    _refreshAuthorStates();
    _recordSelectionMode();
    final selected = _authors
        .where((author) => author.selectionState != AuthorSelectionState.none)
        .toList();
    _publishDebugState();
    Navigator.pop(
      context,
      MultiHomeSelectionResult(
        selectedAuthors: selected,
        qualityMode: _qualityMode,
        worksBySecUid: {
          for (final entry in _worksBySecUid.entries)
            entry.key: List<SaveWorkItem>.unmodifiable(entry.value),
        },
      ),
    );
  }

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
                    onTap: _toggleQualityMode,
                  ),
                  const SizedBox(width: 6),
                  SaveCategoryFilterButton(
                    key: const ValueKey('home_select_all_btn'),
                    label: '全选',
                    hasItems: _hasAuthors,
                    isSelected: _isAllSelected,
                    onTap: _toggleSelectAll,
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
                itemBuilder: (context, index) => _buildAuthorTile(index),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: const ValueKey('multi_home_confirm_btn'),
                  onPressed: _selectedCount == 0 ? null : _confirm,
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

  void _publishDebugState() {
    SavePageDebugStore.update('top', {
      'qualityMode': _qualityMode.name,
      'authors': [
        for (var index = 0; index < _authors.length; index++)
          _authorDebug(index),
      ],
    });
  }

  Map<String, dynamic> _authorDebug(int index) {
    final author = _authors[index];
    final works = _worksOf(author.profile.secUid.trim());
    return {
      'index': index,
      'secUid': author.profile.secUid,
      'nickname': author.profile.nickname,
      'state': author.selectionState.name,
      'worksCount': works.length,
      'selectedWorks': works.where((work) => work.selectionState.isSelected).length,
      'works': [for (final work in works) _workDebug(work)],
    };
  }

  Map<String, dynamic> _workDebug(SaveWorkItem work) {
    return {
      'url': work.url,
      'kind': work.kind.name,
      'state': work.selectionState.name,
      'quality': work.qualityChoice.level.name,
      'selectedResourceCount': work.selectedResources.length,
      'selectedResourceUrls': [
        for (final item in work.selectedResources) item.url,
      ],
    };
  }

  Widget _buildAuthorTile(int index) {
    final author = _authors[index];
    final state = author.selectionState;
    final isPartial = state == AuthorSelectionState.partial;
    final isAll = state == AuthorSelectionState.all;

    final Widget clippedAvatar = ClipRRect(
      borderRadius: BorderRadius.circular(9),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _AuthorAvatarContent(
            avatarUrl: author.profile.avatarUrl,
            headers: widget.headers,
          ),
          if (author.profile.nickname.isNotEmpty)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.fromLTRB(6, 14, 28, 4),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.transparent,
                      Colors.black.withValues(alpha: 0.65),
                    ],
                  ),
                ),
                child: Text(
                  author.profile.nickname,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          Positioned(
            bottom: 4,
            right: 4,
            child: SaveOpenBadge(
              key: ValueKey('open_author_button_$index'),
              semanticLabel: '打开作者作品列表',
              onTap: () => _handleOpenAuthor(index),
            ),
          ),
          if (_openingIndex == index)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.35),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );

    final tile = GestureDetector(
      key: ValueKey('author_tile_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleAuthor(index),
      child: SaveSelectionFrame(
        selected: isAll,
        partial: isPartial,
        partialKey: ValueKey('author_partial_border_$index'),
        child: clippedAvatar,
      ),
    );

    return Semantics(
      container: true,
      button: true,
      selected: isAll,
      value: isPartial ? '部分选择' : (isAll ? '全选' : '未选'),
      label: author.profile.nickname.isNotEmpty
          ? author.profile.nickname
          : '作者 ${index + 1}',
      child: tile,
    );
  }
}

/// 作者头像内容组件（带加载中与兜底占位）
class _AuthorAvatarContent extends StatelessWidget {
  const _AuthorAvatarContent({required this.avatarUrl, required this.headers});

  final String avatarUrl;
  final Map<String, String> headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final placeholderColor = isDark
        ? theme.colorScheme.surfaceContainerHighest
        : theme.colorScheme.surfaceContainerHigh;

    if (avatarUrl.trim().isEmpty) {
      return Container(
        color: placeholderColor,
        child: Icon(
          Icons.person_outline_rounded,
          size: 36,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    return Image.network(
      avatarUrl,
      headers: headers,
      cacheWidth: 360,
      fit: BoxFit.cover,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: placeholderColor,
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        );
      },
      errorBuilder: (_, _, _) => Container(
        color: placeholderColor,
        child: Icon(
          Icons.person_outline_rounded,
          size: 36,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
