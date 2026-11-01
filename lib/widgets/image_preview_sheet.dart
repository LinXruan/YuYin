import 'package:flutter/material.dart';

import '../models/media_item.dart';
import '../services/audio_preview_service.dart';
import '../utils/selection_mode_store.dart';

/// 图片/实况图/配乐音频预览面板：网格展示所有资源，支持分类快速筛选、音频试听、放大预览与批量保存。
class ImagePreviewSheet extends StatefulWidget {
  const ImagePreviewSheet({
    super.key,
    required this.items,
    required this.headers,
    this.audioService,
  });

  final List<MediaItem> items;

  /// 加载网络图片所需的请求头（User-Agent、Referer）
  final Map<String, String> headers;

  /// 可选注入音频服务（便于测试 Mock）
  final AudioPreviewService? audioService;

  /// 弹出面板，返回用户勾选的资源；用户取消时返回 null。
  static Future<List<MediaItem>?> show(
    BuildContext context, {
    required List<MediaItem> items,
    required Map<String, String> headers,
    AudioPreviewService? audioService,
  }) {
    return showModalBottomSheet<List<MediaItem>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImagePreviewSheet(
        items: items,
        headers: headers,
        audioService: audioService,
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
    for (var i = 0; i < widget.items.length; i++) {
      final type = widget.items[i].type;
      if (SelectionModeStore.getMode(type) != 2) {
        _selectedIndices.add(i);
      }
    }

    if (widget.audioService != null) {
      _audioService = widget.audioService!;
    } else {
      _audioService = AudioPreviewService();
      _createdOwnAudioService = true;
    }
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
    _audioService.stop();
    final selected = _selectedIndices.toList()..sort();
    Navigator.pop(context, [
      for (final index in selected) widget.items[index],
    ]);
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
                    final value =
                        total != null && total > 0 ? loaded / total : null;
                    return Center(
                      child: CircularProgressIndicator(
                        value: value,
                        strokeWidth: 2,
                      ),
                    );
                  },
                  errorBuilder: (_, _, _) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: Colors.white),
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
                  _CategoryFilterButton(
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
                  _CategoryFilterButton(
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
                  _CategoryFilterButton(
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
              _buildAudioPlayerBar(theme),
            // 保存按钮
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _selectedIndices.isEmpty ? null : _confirm,
                  icon: const Icon(Icons.save_alt),
                  label: Text(
                    '保存选中项 (${_selectedIndices.length})',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 底部配乐试听播放条
  Widget _buildAudioPlayerBar(ThemeData theme) {
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: isDark
            ? theme.colorScheme.surfaceContainerHighest
            : theme.colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // 左侧大号播放/暂停按钮
          ValueListenableBuilder<AudioPreviewState>(
            valueListenable: _audioService.state,
            builder: (context, state, _) {
              final isPlaying = state == AudioPreviewState.playing;
              final isBuffering = state == AudioPreviewState.buffering;
              return IconButton.filledTonal(
                iconSize: 26,
                onPressed: () {
                  if (_currentPlayingItem == null) return;
                  if (isPlaying) {
                    _audioService.pause();
                  } else {
                    _audioService.play(
                      _currentPlayingItem!.url,
                      headers: widget.headers,
                    );
                  }
                },
                icon: isBuffering
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Icon(
                        isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
              );
            },
          ),
          const SizedBox(width: 10),
          // 中间信息与可滑动进度条
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.music_note_rounded,
                      size: 16,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        _currentPlayingItem?.gearName ?? '音频试听',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ValueListenableBuilder<Duration>(
                      valueListenable: _audioService.position,
                      builder: (context, pos, _) {
                        return ValueListenableBuilder<Duration>(
                          valueListenable: _audioService.duration,
                          builder: (context, dur, _) {
                            return Text(
                              '${_formatDuration(pos)} / ${_formatDuration(dur)}',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                // 支持手势水平滑动的无滑块平滑进度条
                _ScrubbableProgressBar(
                  key: const ValueKey('scrubbable_progress_bar'),
                  audioService: _audioService,
                  theme: theme,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // 右侧关闭按钮（叉）
          IconButton(
            key: const ValueKey('audio_player_close_button'),
            icon: const Icon(Icons.close_rounded),
            tooltip: '关闭播放条',
            onPressed: _closeAudioPlayerBar,
          ),
        ],
      ),
    );
  }

  /// 单个网格项：点击缩略图本身切换勾选，选中状态体现为 3.0dp 边框，右下角提供专属微型预览/播放按钮
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
          return const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        },
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.broken_image_outlined),
        ),
      );
    } else if (isAudio) {
      content = _AudioTile(item: item);
    } else {
      content = _LiveVideoTile(item: item);
    }

    return GestureDetector(
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
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }
}

/// 支持无滑块手势横向拖动与轻触定位的平滑进度条
class _ScrubbableProgressBar extends StatefulWidget {
  const _ScrubbableProgressBar({
    super.key,
    required this.audioService,
    required this.theme,
  });

  final AudioPreviewService audioService;
  final ThemeData theme;

  @override
  State<_ScrubbableProgressBar> createState() => _ScrubbableProgressBarState();
}

class _ScrubbableProgressBarState extends State<_ScrubbableProgressBar> {
  bool _isDragging = false;
  double _dragRatio = 0.0;

  void _updateDrag(Offset localPosition, double width) {
    if (width <= 0) return;
    // 比例算法：横向移动距离占进度条总宽度的比例
    final ratio = (localPosition.dx / width).clamp(0.0, 1.0);
    setState(() {
      _dragRatio = ratio;
    });
    final total = widget.audioService.duration.value.inMilliseconds;
    if (total > 0) {
      widget.audioService.position.value =
          Duration(milliseconds: (total * ratio).round());
    }
  }

  void _finishDrag() {
    if (!_isDragging) return;
    _isDragging = false;
    final total = widget.audioService.duration.value.inMilliseconds;
    if (total > 0) {
      final target = Duration(milliseconds: (total * _dragRatio).round());
      widget.audioService.seek(target);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (details) {
            _isDragging = true;
            _updateDrag(details.localPosition, width);
          },
          onHorizontalDragUpdate: (details) {
            _updateDrag(details.localPosition, width);
          },
          onHorizontalDragEnd: (details) {
            _finishDrag();
          },
          onHorizontalDragCancel: () {
            _finishDrag();
          },
          onTapDown: (details) {
            _isDragging = true;
            _updateDrag(details.localPosition, width);
            _finishDrag();
          },
          child: Container(
            height: 20, // 宽适的触摸感应区，极佳的滑动体验
            alignment: Alignment.center,
            child: ValueListenableBuilder<Duration>(
              valueListenable: widget.audioService.position,
              builder: (context, pos, _) {
                return ValueListenableBuilder<Duration>(
                  valueListenable: widget.audioService.duration,
                  builder: (context, dur, _) {
                    final total = dur.inMilliseconds;
                    final current = pos.inMilliseconds;
                    final progress = _isDragging
                        ? _dragRatio
                        : (total > 0 ? (current / total).clamp(0.0, 1.0) : 0.0);

                    return ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          // 进度条底层背景
                          Container(
                            height: 5,
                            width: double.infinity,
                            color: theme.colorScheme.surfaceContainerHighest,
                          ),
                          // 进度条前景填充（无滑块，距离与手指完全同步）
                          FractionallySizedBox(
                            widthFactor: progress.toDouble(),
                            child: Container(
                              height: 5,
                              color: theme.colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// 顶部类型分类筛选切换按钮（“图片”、“实况”、“音频”）
class _CategoryFilterButton extends StatelessWidget {
  const _CategoryFilterButton({
    super.key,
    required this.label,
    required this.hasItems,
    required this.isSelected,
    required this.onTap,
  });

  final String label;
  final bool hasItems;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (!hasItems) {
      // 缺少该资源类型：蒙上灰色，不可点击
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: isDark
              ? Colors.white.withValues(alpha: 0.04)
              : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
            width: 1.0,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.28),
          ),
        ),
      );
    }

    // 存在资源：选中时展示高亮边框
    final borderColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.outlineVariant;
    final backgroundColor = isSelected
        ? theme.colorScheme.primary.withValues(alpha: isDark ? 0.18 : 0.10)
        : Colors.transparent;
    final textColor = isSelected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: borderColor,
            width: isSelected ? 2.0 : 1.0,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: textColor,
          ),
        ),
      ),
    );
  }
}

/// 实况视频占位图
class _LiveVideoTile extends StatelessWidget {
  const _LiveVideoTile({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.motion_photos_on, color: Colors.white, size: 30),
          const SizedBox(height: 6),
          const Text(
            '实况视频 (LIVE)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (item.resolution?.isNotEmpty == true)
            Text(
              item.resolution!,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }
}

/// 图文配乐音频卡片：删掉“BGM 音频”，音符与“音频”居中显示
class _AudioTile extends StatelessWidget {
  const _AudioTile({
    required this.item,
  });

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Container(
      color: isDark
          ? theme.colorScheme.surfaceContainerHighest
          : theme.colorScheme.surfaceContainerHigh,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.music_note_rounded,
            color: theme.colorScheme.primary,
            size: 32,
          ),
          const SizedBox(height: 6),
          Text(
            '音频',
            textAlign: TextAlign.center,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}
