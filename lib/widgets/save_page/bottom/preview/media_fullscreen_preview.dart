import 'package:flutter/material.dart';

import '../../../../models/single_work/media_download_item.dart';

/// 底层大图全屏预览弹窗（支持多图左右滑动切换与双指缩放）
abstract final class MediaFullscreenPreview {
  /// 显示全屏大图预览弹窗
  static void show(
    BuildContext context, {
    required List<MediaItem> items,
    int initialIndex = 0,
    required Map<String, String> headers,
  }) {
    if (items.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, items.length - 1);
    showDialog<void>(
      context: context,
      builder: (_) => _FullscreenGalleryDialog(
        items: items,
        initialIndex: safeIndex,
        headers: headers,
      ),
    );
  }
}

class _FullscreenGalleryDialog extends StatefulWidget {
  const _FullscreenGalleryDialog({
    required this.items,
    required this.initialIndex,
    required this.headers,
  });

  final List<MediaItem> items;
  final int initialIndex;
  final Map<String, String> headers;

  @override
  State<_FullscreenGalleryDialog> createState() =>
      _FullscreenGalleryDialogState();
}

class _FullscreenGalleryDialogState extends State<_FullscreenGalleryDialog> {
  late final PageController _pageController;
  late int _currentIndex;
  bool _isZoomed = false;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _pageController,
              physics: _isZoomed
                  ? const NeverScrollableScrollPhysics()
                  : const PageScrollPhysics(),
              itemCount: widget.items.length,
              onPageChanged: (index) {
                setState(() {
                  _currentIndex = index;
                  _isZoomed = false;
                });
              },
              itemBuilder: (context, index) {
                return _ZoomableNetworkImage(
                  url: widget.items[index].url,
                  headers: widget.headers,
                  onZoomChanged: (zoomed) {
                    if (_isZoomed != zoomed) {
                      setState(() => _isZoomed = zoomed);
                    }
                  },
                );
              },
            ),
          ),
          if (widget.items.length > 1)
            Positioned(
              top: 18,
              left: 16,
              child: Container(
                key: const ValueKey('fullscreen_page_indicator'),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.55),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  '${_currentIndex + 1} / ${widget.items.length}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
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
    );
  }
}

class _ZoomableNetworkImage extends StatefulWidget {
  const _ZoomableNetworkImage({
    required this.url,
    required this.headers,
    required this.onZoomChanged,
  });

  final String url;
  final Map<String, String> headers;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableNetworkImage> createState() => _ZoomableNetworkImageState();
}

class _ZoomableNetworkImageState extends State<_ZoomableNetworkImage> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncZoomState() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed != _zoomed) {
      setState(() => _zoomed = zoomed);
      widget.onZoomChanged(zoomed);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      transformationController: _controller,
      minScale: 0.8,
      maxScale: 4,
      panEnabled: _zoomed,
      onInteractionEnd: (_) => _syncZoomState(),
      onInteractionUpdate: (_) => _syncZoomState(),
      child: Image.network(
        widget.url,
        headers: widget.headers,
        fit: BoxFit.contain,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          final total = progress.expectedTotalBytes;
          final loaded = progress.cumulativeBytesLoaded;
          final value = total != null && total > 0 ? loaded / total : null;
          return Center(
            child: CircularProgressIndicator(value: value, strokeWidth: 2),
          );
        },
        errorBuilder: (_, _, _) => const Center(
          child: Icon(Icons.broken_image_outlined, color: Colors.white),
        ),
      ),
    );
  }
}
