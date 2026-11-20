import 'dart:io';

import 'package:flutter/material.dart';

import '../../utils/thumbnail/history_thumbnail_cache.dart';

/// 本地缩略图：同步命中优先，未命中时只发起一次后台加载并监听缓存更新。
///
/// 取代 `build()` 内创建 `FutureBuilder` 的写法：滚动或整页通知不会重复发起
/// 磁盘查询，也不会让整个列表重建。
class CachedThumbnailImage extends StatefulWidget {
  const CachedThumbnailImage({
    super.key,
    required this.cacheId,
    required this.coverUrl,
    required this.size,
    required this.placeholder,
    required this.imageBuilder,
  });

  final String cacheId;
  final String coverUrl;
  final double size;
  final Widget placeholder;
  final Widget Function(File file) imageBuilder;

  @override
  State<CachedThumbnailImage> createState() => _CachedThumbnailImageState();
}

class _CachedThumbnailImageState extends State<CachedThumbnailImage> {
  File? _file;
  bool _requested = false;

  @override
  void initState() {
    super.initState();
    HistoryThumbnailCache.cacheUpdateNotifier.addListener(_onCacheUpdated);
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CachedThumbnailImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.cacheId != widget.cacheId ||
        oldWidget.coverUrl != widget.coverUrl) {
      _file = null;
      _requested = false;
      _resolve();
    }
  }

  @override
  void dispose() {
    HistoryThumbnailCache.cacheUpdateNotifier.removeListener(_onCacheUpdated);
    super.dispose();
  }

  void _resolve() {
    final cached = HistoryThumbnailCache.getCachedFileSync(widget.cacheId);
    if (cached != null) {
      _file = cached;
      return;
    }
    if (!_requested) {
      _requested = true;
      HistoryThumbnailCache.cacheThumbnail(widget.cacheId, widget.coverUrl);
    }
    final id = widget.cacheId;
    HistoryThumbnailCache.findValidCachedFile(id).then((file) {
      if (!mounted || file == null || widget.cacheId != id) return;
      setState(() => _file = file);
    });
  }

  void _onCacheUpdated() {
    if (_file != null || !mounted) return;
    final cached = HistoryThumbnailCache.getCachedFileSync(widget.cacheId);
    if (cached != null) {
      setState(() => _file = cached);
    }
  }

  @override
  Widget build(BuildContext context) {
    final file = _file;
    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: file == null ? widget.placeholder : widget.imageBuilder(file),
    );
  }
}
