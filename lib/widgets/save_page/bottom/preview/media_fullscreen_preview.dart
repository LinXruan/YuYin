import 'package:flutter/material.dart';

import '../../../../models/single_work/media_download_item.dart';

/// 底层大图全屏预览弹窗（支持多图左右滑动切换、双指捏合放缩与双击放缩）
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
  final Set<int> _activePointers = <int>{};
  bool _isZoomed = false;

  bool get _lockPageScroll =>
      widget.items.length <= 1 || _isZoomed || _activePointers.length >= 2;

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

  void _onPointerDown(PointerDownEvent event) {
    final wasMulti = _activePointers.length >= 2;
    _activePointers.add(event.pointer);
    if (!wasMulti && _activePointers.length >= 2 && mounted) {
      setState(() {});
    }
  }

  void _onPointerEnd(int pointer) {
    final wasMulti = _activePointers.length >= 2;
    _activePointers.remove(pointer);
    if (wasMulti && _activePointers.length < 2 && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final isMultiTouch = _activePointers.length >= 2;
    return Dialog.fullscreen(
      backgroundColor: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(
            child: Listener(
              onPointerDown: _onPointerDown,
              onPointerUp: (e) => _onPointerEnd(e.pointer),
              onPointerCancel: (e) => _onPointerEnd(e.pointer),
              child: PageView.builder(
                controller: _pageController,
                physics: _lockPageScroll
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
                    key: ValueKey<int>(index),
                    url: widget.items[index].url,
                    headers: widget.headers,
                    isCurrentPage: index == _currentIndex,
                    isMultiTouch: isMultiTouch,
                    onZoomChanged: (zoomed) {
                      if (_isZoomed != zoomed && mounted) {
                        setState(() => _isZoomed = zoomed);
                      }
                    },
                  );
                },
              ),
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
    super.key,
    required this.url,
    required this.headers,
    required this.isCurrentPage,
    required this.isMultiTouch,
    required this.onZoomChanged,
  });

  final String url;
  final Map<String, String> headers;
  final bool isCurrentPage;
  final bool isMultiTouch;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_ZoomableNetworkImage> createState() => _ZoomableNetworkImageState();
}

class _ZoomableNetworkImageState extends State<_ZoomableNetworkImage> {
  final TransformationController _controller = TransformationController();
  bool _zoomed = false;
  TapDownDetails? _doubleTapDetails;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncZoomState);
  }

  @override
  void didUpdateWidget(covariant _ZoomableNetworkImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.isCurrentPage && !widget.isCurrentPage) {
      if (_controller.value != Matrix4.identity()) {
        _controller.value = Matrix4.identity();
      }
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncZoomState);
    _controller.dispose();
    super.dispose();
  }

  void _syncZoomState() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed != _zoomed) {
      if (mounted) {
        setState(() => _zoomed = zoomed);
      }
      widget.onZoomChanged(zoomed);
    }
  }

  void _handleDoubleTap() {
    if (_zoomed) {
      _controller.value = Matrix4.identity();
      return;
    }
    final size = context.size ?? Size.zero;
    final focal = _doubleTapDetails?.localPosition ??
        Offset(size.width / 2, size.height / 2);
    const targetScale = 2.5;
    final minX = -size.width * (targetScale - 1);
    final minY = -size.height * (targetScale - 1);
    final dx = size.width > 0
        ? (focal.dx * (1 - targetScale)).clamp(minX, 0.0)
        : 0.0;
    final dy = size.height > 0
        ? (focal.dy * (1 - targetScale)).clamp(minY, 0.0)
        : 0.0;
    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, targetScale)
      ..setEntry(1, 1, targetScale)
      ..setEntry(0, 3, dx)
      ..setEntry(1, 3, dy);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onDoubleTapDown: (details) => _doubleTapDetails = details,
      onDoubleTap: _handleDoubleTap,
      child: InteractiveViewer(
        transformationController: _controller,
        minScale: 1.0,
        maxScale: 4.0,
        panEnabled: _zoomed || widget.isMultiTouch,
        scaleEnabled: true,
        child: SizedBox.expand(
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
        ),
      ),
    );
  }
}
