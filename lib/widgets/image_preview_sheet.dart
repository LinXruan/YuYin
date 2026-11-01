import 'package:flutter/material.dart';

import '../models/media_item.dart';

/// 图片/实况图预览面板：网格展示所有资源，支持全选、反选、放大预览。
class ImagePreviewSheet extends StatefulWidget {
  const ImagePreviewSheet({
    super.key,
    required this.items,
    required this.headers,
  });

  final List<MediaItem> items;

  /// 加载网络图片所需的请求头（User-Agent、Referer）
  final Map<String, String> headers;

  /// 弹出面板，返回用户勾选的资源；用户取消时返回 null。
  static Future<List<MediaItem>?> show(
    BuildContext context, {
    required List<MediaItem> items,
    required Map<String, String> headers,
  }) {
    return showModalBottomSheet<List<MediaItem>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImagePreviewSheet(items: items, headers: headers),
    );
  }

  @override
  State<ImagePreviewSheet> createState() => _ImagePreviewSheetState();
}

class _ImagePreviewSheetState extends State<ImagePreviewSheet> {
  late final Set<int> _selectedIndices;

  @override
  void initState() {
    super.initState();
    // 默认所有资源都处于选中状态
    _selectedIndices = {
      for (var i = 0; i < widget.items.length; i++) i,
    };
  }

  /// 切换单个资源的选中状态
  void _toggleSelected(int index) {
    setState(() {
      if (!_selectedIndices.remove(index)) _selectedIndices.add(index);
    });
  }

  /// 全选 / 取消全选
  void _toggleSelectAll() {
    setState(() {
      if (_selectedIndices.length == widget.items.length) {
        _selectedIndices.clear();
      } else {
        _selectedIndices.addAll(
          List.generate(widget.items.length, (index) => index),
        );
      }
    });
  }

  /// 返回按原始顺序排列的选中资源
  void _confirm() {
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
    final allSelected = _selectedIndices.length == widget.items.length;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.8,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选 ${_selectedIndices.length} / ${widget.items.length} 项',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                  TextButton(
                    onPressed: _toggleSelectAll,
                    child: Text(allSelected ? '取消全选' : '全选'),
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
                itemCount: widget.items.length,
                itemBuilder: (context, index) => _buildTile(index),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed:
                      _selectedIndices.isEmpty ? null : _confirm,
                  icon: const Icon(Icons.save_alt),
                  label: Text(
                    '保存选中项 (${_selectedIndices.length}) ',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 单个网格：图片显示缩略图，实况视频显示 LIVE 占位图，音频显示音符卡片
  Widget _buildTile(int index) {
    final item = widget.items[index];
    final selected = _selectedIndices.contains(index);
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
      onTap: isImage ? () => _showPreview(item) : () => _toggleSelected(index),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: () => _toggleSelected(index),
                child: Container(
                  decoration: const BoxDecoration(
                    color: Colors.black45,
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    selected
                        ? Icons.check_circle
                        : Icons.radio_button_unchecked,
                    color: selected
                        ? Theme.of(context).colorScheme.primary
                        : Colors.white,
                    size: 22,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 实况视频占位图，避免为了缩略图再引入视频播放依赖
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

/// 图文配乐音频占位卡片
class _AudioTile extends StatelessWidget {
  const _AudioTile({required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.all(6),
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
            item.gearName ?? '配乐音频',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'BGM 音频',
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
