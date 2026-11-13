import 'package:flutter/material.dart';

import '../../models/common/save_memory_scope.dart';
import '../../models/media_item.dart';
import '../../services/audio_preview_service.dart';
import '../../utils/save_page_debug_store.dart';
import '../../utils/selection_mode_store.dart';
import 'bottom_media_widgets.dart';
import 'save_page_common.dart';

part 'bottom/flow/bottom_media_selection_flow.dart';

part 'bottom/flow/bottom_audio_flow.dart';

part 'bottom/flow/bottom_selection_memory.dart';

part 'bottom/flow/bottom_confirm_flow.dart';

part 'bottom/flow/bottom_preview_flow.dart';

part 'bottom/debug/bottom_debug_snapshot.dart';

part 'bottom/widget/bottom_media_tile.dart';

/// 图片/实况图/配乐音频预览面板：网格展示所有资源，支持分类快速筛选、音频试听、放大预览与批量保存。
class ImagePreviewSheet extends StatefulWidget {
  const ImagePreviewSheet({
    super.key,
    required this.items,
    required this.headers,
    this.audioService,
    this.nested = false,
    this.initialSelectedUrls,
    this.memoryScope = SaveMemoryScope.singleBottom,
  });

  final List<MediaItem> items;

  /// 加载网络图片所需的请求头（User-Agent、Referer）
  final Map<String, String> headers;

  /// 可选注入音频服务（便于测试 Mock）
  final AudioPreviewService? audioService;

  /// true 表示由中层进入底层，底部按钮显示“返回”
  final bool nested;

  /// 再次进入底层时用于恢复已选资源；为 null 时按分类记忆默认值初始化
  final Set<String>? initialSelectedUrls;

  /// 底层记忆作用域：homeBottom / multiBottom / singleBottom
  final SaveMemoryScope memoryScope;

  /// 弹出面板，返回用户勾选的资源；用户取消时返回 null。
  static Future<List<MediaItem>?> show(
    BuildContext context, {
    required List<MediaItem> items,
    required Map<String, String> headers,
    AudioPreviewService? audioService,
    bool nested = false,
    Set<String>? initialSelectedUrls,
    SaveMemoryScope memoryScope = SaveMemoryScope.singleBottom,
  }) {
    return showModalBottomSheet<List<MediaItem>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImagePreviewSheet(
        items: items,
        headers: headers,
        audioService: audioService,
        nested: nested,
        initialSelectedUrls: initialSelectedUrls,
        memoryScope: memoryScope,
      ),
    );
  }

  @override
  State<ImagePreviewSheet> createState() => _ImagePreviewSheetState();
}

class _ImagePreviewSheetState extends State<ImagePreviewSheet> {
  late final Set<int> _selectedIndices;
  late final AudioPreviewService _audioService;
  bool _createdOwnAudioService = false;
  bool _hasRecordedSelection = false;

  bool _showAudioPlayerBar = false;
  MediaItem? _currentPlayingItem;

  @override
  void initState() {
    super.initState();
    // 根据每种标签（图片、实况、音频）各自用于下次解析的判断值 a 决定初始选择状态：
    // 若对应标签的 a == 2（全不选），则默认不勾选；默认 (a == 1) 勾选。
    _selectedIndices = <int>{};
    final initialUrls = widget.initialSelectedUrls;
    if (initialUrls != null) {
      // 再次进入：精确恢复该作品上一次的资源选择
      for (var i = 0; i < widget.items.length; i++) {
        if (initialUrls.contains(widget.items[i].url)) {
          _selectedIndices.add(i);
        }
      }
    } else {
      // 首次进入：按图片/实况/音频各自的记忆默认值初始化
      for (var i = 0; i < widget.items.length; i++) {
        final type = widget.items[i].type;
        if (SelectionModeStore.getBottomMode(type, widget.memoryScope) != 2) {
          _selectedIndices.add(i);
        }
      }
    }

    if (widget.audioService != null) {
      _audioService = widget.audioService!;
    } else {
      _audioService = AudioPreviewService();
      _createdOwnAudioService = true;
    }
    this._publishDebugState();
  }

  @override
  void dispose() {
    this._recordSelectionMode();
    if (_createdOwnAudioService) {
      _audioService.dispose();
    } else {
      _audioService.stop();
    }
    super.dispose();
  }

  /// 供流程分片调用的状态刷新入口
  void _refresh(VoidCallback fn) => setState(fn);

  /// 根据当前选择情况，按标签分别计算判断值 b 并驱动各标签 a 状态转移
  List<int> get _imageIndices => [
    for (var i = 0; i < widget.items.length; i++)
      if (widget.items[i].type == MediaType.image) i,
  ];

  List<int> get _liveIndices => [
    for (var i = 0; i < widget.items.length; i++)
      if (widget.items[i].type == MediaType.video) i,
  ];

  List<int> get _audioIndices => [
    for (var i = 0; i < widget.items.length; i++)
      if (widget.items[i].type == MediaType.audio) i,
  ];

  bool get _hasImages => _imageIndices.isNotEmpty;
  bool get _hasLive => _liveIndices.isNotEmpty;
  bool get _hasAudio => _audioIndices.isNotEmpty;

  bool get _isAllImagesSelected =>
      _hasImages && _imageIndices.every(_selectedIndices.contains);
  bool get _isAllLiveSelected =>
      _hasLive && _liveIndices.every(_selectedIndices.contains);
  bool get _isAllAudioSelected =>
      _hasAudio && _audioIndices.every(_selectedIndices.contains);

  /// 切换单个资源的选中状态
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.82,
        child: Column(
          children: [
            // 顶部选择状态与分类筛选切换栏
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 ${_selectedIndices.length} / ${widget.items.length} 项',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 分类切换按钮组：“图片”、“实况”、“音频”
                  SaveCategoryFilterButton(
                    key: const ValueKey('category_btn_image'),
                    label: '图片',
                    hasItems: _hasImages,
                    isSelected: _isAllImagesSelected,
                    onTap: () => this._toggleCategory(
                      _imageIndices,
                      _isAllImagesSelected,
                      _hasImages,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SaveCategoryFilterButton(
                    key: const ValueKey('category_btn_live'),
                    label: '实况',
                    hasItems: _hasLive,
                    isSelected: _isAllLiveSelected,
                    onTap: () => this._toggleCategory(
                      _liveIndices,
                      _isAllLiveSelected,
                      _hasLive,
                    ),
                  ),
                  const SizedBox(width: 6),
                  SaveCategoryFilterButton(
                    key: const ValueKey('category_btn_audio'),
                    label: '音频',
                    hasItems: _hasAudio,
                    isSelected: _isAllAudioSelected,
                    onTap: () => this._toggleCategory(
                      _audioIndices,
                      _isAllAudioSelected,
                      _hasAudio,
                    ),
                  ),
                ],
              ),
            ),
            // 资源预览网格
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemCount: widget.items.length,
                itemBuilder: (context, index) => this._buildTile(index),
              ),
            ),
            // 底部配乐播放条（点击音频播放按钮后呼出）
            if (_showAudioPlayerBar && _currentPlayingItem != null)
              MediaAudioPlayerBar(
                audioService: _audioService,
                item: _currentPlayingItem!,
                headers: widget.headers,
                onClose: this._closeAudioPlayerBar,
              ),
            // 保存按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  key: ValueKey(
                    widget.nested ? 'bottom_back_button' : 'bottom_save_button',
                  ),
                  onPressed: widget.nested
                      ? this._confirm
                      : (_selectedIndices.isEmpty ? null : this._confirm),
                  icon: Icon(
                    widget.nested ? Icons.arrow_back_rounded : Icons.save_alt,
                  ),
                  label: Text(
                    widget.nested ? '返回' : '保存选中项 (${_selectedIndices.length})',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个网格项：点击缩略图本身切换勾选，选中状态体现为 3.0dp 边框，右下角提供专属微型预览/播放按钮
}

// ignore_for_file: unnecessary_this
