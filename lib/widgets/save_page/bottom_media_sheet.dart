import 'package:flutter/material.dart';

import '../../models/common/work_type.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/work_selection_view.dart';
import '../../models/single_work/media_download_item.dart';
import '../../services/media/audio_preview_service.dart';
import '../../services/selection/save_selection_session.dart';
import '../../utils/debug/save_page_debug_store.dart';
import 'bottom/debug/bottom_debug_snapshot_helper.dart';
import 'bottom/preview/media_fullscreen_preview.dart';
import 'bottom/widget/bottom_media_tile.dart';
import 'bottom/widget/media_audio_player_bar.dart';
import 'filter/filter_controls.dart';

/// 底层保存页：图片 / 实况 / 配乐资源网格
///
/// 视频作品的底层入口是画质面板，不进入本页面。
class ImagePreviewSheet extends StatefulWidget {
  const ImagePreviewSheet({
    super.key,
    required this.session,
    required this.workUrl,
    required this.items,
    required this.headers,
    this.audioService,
    this.nested = false,
    this.debugStore,
  });

  final SaveSelectionSession session;

  final String workUrl;

  final List<MediaItem> items;

  final Map<String, String> headers;

  final AudioPreviewService? audioService;

  /// true 表示由中层进入，底部按钮显示“返回”
  final bool nested;

  final SavePageDebugStore? debugStore;

  static Future<bool?> show(
    BuildContext context, {
    required SaveSelectionSession session,
    required String workUrl,
    required List<MediaItem> items,
    required Map<String, String> headers,
    AudioPreviewService? audioService,
    bool nested = false,
    SavePageDebugStore? debugStore,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ImagePreviewSheet(
        session: session,
        workUrl: workUrl,
        items: items,
        headers: headers,
        audioService: audioService,
        nested: nested,
        debugStore: debugStore,
      ),
    );
  }

  @override
  State<ImagePreviewSheet> createState() => _ImagePreviewSheetState();
}

class _ImagePreviewSheetState extends State<ImagePreviewSheet> {
  late final AudioPreviewService _audioService;
  bool _createdOwnAudioService = false;

  bool _showAudioPlayerBar = false;
  MediaItem? _currentPlayingItem;

  WorkSelectionView? get _row => widget.session.workOf(widget.workUrl);

  @override
  void initState() {
    super.initState();
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
    if (_createdOwnAudioService) {
      _audioService.dispose();
    } else {
      _audioService.stop();
    }
    super.dispose();
  }

  void _publishDebugState() {
    BottomDebugSnapshotHelper.publish(
      widget.session,
      widget.workUrl,
      debugStore: widget.debugStore,
    );
  }

  AggregateState _resourceState(MediaType type) =>
      _row?.resourceState(type) ?? AggregateState.empty;

  bool _isSelected(MediaItem item) {
    final row = _row;
    if (row == null) return false;
    for (final resource in row.resources) {
      if (resource.key == item.url) return resource.selected;
    }
    return false;
  }

  void _toggleSelected(int index) {
    widget.session.toggleResource(widget.workUrl, widget.items[index].url);
    _publishDebugState();
  }

  void _toggleCategory(MediaType type) {
    widget.session.toggleResourceCategory(widget.workUrl, type);
    _publishDebugState();
  }

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

  void _closeAudioPlayerBar() {
    _audioService.stop();
    setState(() {
      _showAudioPlayerBar = false;
      _currentPlayingItem = null;
    });
  }

  void _showPreview(MediaItem item) {
    final imageItems =
        widget.items.where((m) => m.type == MediaType.image).toList();
    final items = imageItems.isEmpty ? [item] : imageItems;
    final initialIndex = items.indexWhere((m) => m.url == item.url);
    MediaFullscreenPreview.show(
      context,
      items: items,
      initialIndex: initialIndex < 0 ? 0 : initialIndex,
      headers: widget.headers,
    );
  }

  void _confirm() {
    _publishDebugState();
    _audioService.stop();
    Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final selectedCount =
            widget.session.selectedResourceCount(widget.workUrl);
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
                          '已选 $selectedCount / ${widget.items.length} 项',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      SaveCategoryFilterButton(
                        key: const ValueKey('category_btn_image'),
                        label: '图片',
                        state: _resourceState(MediaType.image),
                        onTap: () => _toggleCategory(MediaType.image),
                      ),
                      const SizedBox(width: 6),
                      SaveCategoryFilterButton(
                        key: const ValueKey('category_btn_live'),
                        label: '实况',
                        state: _resourceState(MediaType.video),
                        onTap: () => _toggleCategory(MediaType.video),
                      ),
                      const SizedBox(width: 6),
                      SaveCategoryFilterButton(
                        key: const ValueKey('category_btn_audio'),
                        label: '音频',
                        state: _resourceState(MediaType.audio),
                        onTap: () => _toggleCategory(MediaType.audio),
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
                    itemBuilder: (context, index) {
                      final item = widget.items[index];
                      return BottomMediaTile(
                        index: index,
                        item: item,
                        selected: _isSelected(item),
                        headers: widget.headers,
                        onTap: () => _toggleSelected(index),
                        onPreview: _showPreview,
                        audioService: _audioService,
                        currentPlayingItem: _currentPlayingItem,
                        onTogglePlayAudio: _togglePlayAudio,
                      );
                    },
                  ),
                ),
                if (_showAudioPlayerBar && _currentPlayingItem != null)
                  MediaAudioPlayerBar(
                    audioService: _audioService,
                    item: _currentPlayingItem!,
                    headers: widget.headers,
                    onClose: _closeAudioPlayerBar,
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 12),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      key: ValueKey(
                        widget.nested
                            ? 'bottom_back_button'
                            : 'bottom_save_button',
                      ),
                      onPressed: widget.nested
                          ? _confirm
                          : (selectedCount == 0 ? null : _confirm),
                      icon: Icon(
                        widget.nested
                            ? Icons.arrow_back_rounded
                            : Icons.save_alt,
                      ),
                      label: Text(
                        widget.nested ? '返回' : '保存选中项 ($selectedCount)',
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
