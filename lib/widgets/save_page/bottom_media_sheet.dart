import 'package:flutter/material.dart';

import '../../models/common/save_memory_scope.dart';
import '../../models/media_item.dart';
import '../../services/audio_preview_service.dart';
import '../../utils/save_page_debug_store.dart';
import '../../utils/selection_mode_store.dart';
import 'bottom_media_widgets.dart';
import 'save_page_common.dart';

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
    _publishDebugState();
  }

  @override
  void dispose() {
    _recordSelectionMode();
    if (_createdOwnAudioService) {
      _audioService.dispose();
    } else {
      _audioService.stop();
    }
    super.dispose();
  }

  /// 根据当前选择情况，按标签分别计算判断值 b 并驱动各标签 a 状态转移
  void _recordSelectionMode() {
    if (_hasRecordedSelection) return;
    _hasRecordedSelection = true;
    SelectionModeStore.updateFromSheetItems(
      allItems: widget.items,
      selectedIndices: _selectedIndices,
      scope: widget.memoryScope,
    );
  }

  // --- 分类资源索引 ---
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
  void _toggleSelected(int index) {
    setState(() {
      if (!_selectedIndices.remove(index)) _selectedIndices.add(index);
    });
    _publishDebugState();
  }

  /// 按分类一键切换全选/全不选
  void _toggleCategory(List<int> indices, bool isAllSelected, bool hasItems) {
    if (!hasItems) return; // 缺少该类型，点击不响应
    setState(() {
      if (isAllSelected) {
        _selectedIndices.removeAll(indices);
      } else {
        _selectedIndices.addAll(indices);
      }
    });
    _publishDebugState();
  }

  /// 切换指定配乐的试听状态
  void _togglePlayAudio(MediaItem item) {
    if (_currentPlayingItem?.url == item.url) {
      if (_audioService.isPlaying) {
        _audioService.pause();
      } else {
        _audioService.play(item.url, headers: widget.headers);
      }
    } else {
      _currentPlayingItem = item;
      _showAudioPlayerBar = true;
      _audioService.play(item.url, headers: widget.headers);
    }
    setState(() {});
  }

  /// 关闭底部播放条并停止播放
  void _closeAudioPlayerBar() {
    _audioService.stop();
    setState(() {
      _showAudioPlayerBar = false;
      _currentPlayingItem = null;
    });
  }

  /// 返回按原始顺序排列的选中资源
  void _confirm() {
    _recordSelectionMode();
    _publishDebugState();
    _audioService.stop();
    final selected = _selectedIndices.toList()..sort();
    Navigator.pop(context, [for (final index in selected) widget.items[index]]);
  }

  /// 全屏放大预览图片
  void _showPreview(MediaItem item) {
    showDialog<void>(
      context: context,
      builder: (context) => Dialog.fullscreen(
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 4,
                child: Image.network(
                  item.url,
                  headers: widget.headers,
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    final total = progress.expectedTotalBytes;
                    final loaded = progress.cumulativeBytesLoaded;
                    final value = total != null && total > 0
                        ? loaded / total
                        : null;
                    return Center(
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 2,
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 12,
              right: 12,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
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
                    onTap: () => _toggleCategory(
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
                    onTap: () => _toggleCategory(
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
                    onTap: () => _toggleCategory(
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
                itemBuilder: (context, index) => _buildTile(index),
              ),
            ),
            // 底部配乐播放条（点击音频播放按钮后呼出）
            if (_showAudioPlayerBar && _currentPlayingItem != null)
              MediaAudioPlayerBar(
                audioService: _audioService,
                item: _currentPlayingItem!,
                headers: widget.headers,
                onClose: _closeAudioPlayerBar,
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
                      ? _confirm
                      : (_selectedIndices.isEmpty ? null : _confirm),
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
  void _publishDebugState() {
    SavePageDebugStore.update('bottom', {
      'memoryScope': widget.memoryScope.name,
      'nested': widget.nested,
      'selectedCount': _selectedIndices.length,
      'totalCount': widget.items.length,
      'items': [
        for (var index = 0; index < widget.items.length; index++)
          {
            'index': index,
            'url': widget.items[index].url,
            'type': widget.items[index].type.name,
            'selected': _selectedIndices.contains(index),
          },
      ],
    });
  }

  Widget _buildTile(int index) {
    final item = widget.items[index];
    final selected = _selectedIndices.contains(index);
    final theme = Theme.of(context);
    final isImage = item.type == MediaType.image;
    final isAudio = item.type == MediaType.audio;

    final Widget content;
    if (isImage) {
      content = Image.network(
        item.url,
        headers: widget.headers,
        cacheWidth: 360,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const Center(child: CircularProgressIndicator(strokeWidth: 2));
        },
        errorBuilder: (_, _, _) =>
            const Center(child: Icon(Icons.broken_image_outlined)),
      );
    } else if (isAudio) {
      content = const MediaAudioTile();
    } else {
      content = MediaLiveVideoTile(item: item);
    }

    final tile = GestureDetector(
      key: ValueKey('media_tile_$index'),
      behavior: HitTestBehavior.opaque,
      onTap: () => _toggleSelected(index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? theme.colorScheme.primary : Colors.transparent,
            width: 3.0,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(9),
          child: Stack(
            fit: StackFit.expand,
            children: [
              content,
              // 图片资源右下角：微缩版小眼睛按钮（22x22，贴近右下边缘），点击查看大图
              if (isImage)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    key: ValueKey('eye_button_$index'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _showPreview(item),
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.visibility_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                ),
              // 配乐资源右下角：微缩版播放/暂停按钮（22x22，相对位置与小眼睛完全一致）
              if (isAudio)
                Positioned(
                  bottom: 4,
                  right: 4,
                  child: GestureDetector(
                    key: const ValueKey('audio_play_button'),
                    behavior: HitTestBehavior.opaque,
                    onTap: () => _togglePlayAudio(item),
                    child: ValueListenableBuilder<AudioPreviewState>(
                      valueListenable: _audioService.state,
                      builder: (context, state, _) {
                        final isThisPlaying =
                            _currentPlayingItem?.url == item.url &&
                            state == AudioPreviewState.playing;
                        final isThisBuffering =
                            _currentPlayingItem?.url == item.url &&
                            state == AudioPreviewState.buffering;

                        return Container(
                          width: 22,
                          height: 22,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: isThisBuffering
                                ? SizedBox(
                                    width: 10,
                                    height: 10,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 1.5,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : Icon(
                                    isThisPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: theme.colorScheme.onPrimary,
                                    size: 13,
                                  ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );

    final typeLabel = isImage ? '图片' : (isAudio ? '音频' : '实况');
    return Semantics(
      container: true,
      button: true,
      selected: selected,
      label: '$typeLabel ${index + 1}',
      child: tile,
    );
  }
}
