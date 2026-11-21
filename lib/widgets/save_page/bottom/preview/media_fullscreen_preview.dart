import 'package:flutter/material.dart';

import '../../../../models/media_item.dart';

/// 底层大图全屏预览弹窗
abstract final class MediaFullscreenPreview {
  /// 显示全屏大图预览弹窗
  static void show(
    BuildContext context, {
    required MediaItem item,
    required Map<String, String> headers,
  }) {
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
                  headers: headers,
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
}
