import 'package:flutter/material.dart';

import '../../models/common/save_memory_scope.dart';
import '../../models/media_item.dart';
import '../../services/audio_preview_service.dart';
import '../../services/selection/debug/selection_snapshot.dart';
import '../../services/selection/save_selection_session.dart';
import '../../utils/save_page_debug_store.dart';
import '../../utils/selection_mode_store.dart';
import 'bottom_media_widgets.dart';
import 'save_page_common.dart';

part 'bottom/flow/bottom_state_flow.dart';

part 'bottom/flow/bottom_media_selection_flow.dart';

part 'bottom/flow/bottom_audio_flow.dart';

part 'bottom/flow/bottom_selection_memory.dart';

part 'bottom/flow/bottom_confirm_flow.dart';

part 'bottom/flow/bottom_preview_flow.dart';

part 'bottom/debug/bottom_debug_snapshot.dart';

part 'bottom/widget/bottom_media_tile.dart';

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
    this.memoryScope = SaveMemoryScope.singleBottom,
  });

  final SaveSelectionSession session;

  final String workUrl;

  final List<MediaItem> items;

  final Map<String, String> headers;

  final AudioPreviewService? audioService;

  /// true 表示由中层进入，底部按钮显示“返回”
  final bool nested;

  final SaveMemoryScope memoryScope;

  static Future<bool?> show(
    BuildContext context, {
    required SaveSelectionSession session,
    required String workUrl,
    required List<MediaItem> items,
    required Map<String, String> headers,
    AudioPreviewService? audioService,
    bool nested = false,
    SaveMemoryScope memoryScope = SaveMemoryScope.singleBottom,
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
        memoryScope: memoryScope,
      ),
    );
  }

  @override
  State<ImagePreviewSheet> createState() => _ImagePreviewSheetState();
}

class _ImagePreviewSheetState extends State<ImagePreviewSheet> {
  late final AudioPreviewService _audioService;
  bool _createdOwnAudioService = false;
  bool _hasRecordedMemory = false;

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
    _recordSelectionMemory();
    if (_createdOwnAudioService) {
      _audioService.dispose();
    } else {
      _audioService.stop();
    }
    super.dispose();
  }

  /// 供流程分片调用的状态刷新入口
  void _refresh(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.session,
      builder: (context, _) {
        final selectedCount =
            widget.session.selectedResourceCount(widget.workUrl);
        final hasImages = _hasType(MediaType.image);
        final hasLive = _hasType(MediaType.video);
        final hasAudio = _hasType(MediaType.audio);
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
                        hasItems: hasImages,
                        isSelected: _isAllSelected(MediaType.image),
                        onTap: () => _toggleCategory(MediaType.image),
                      ),
                      const SizedBox(width: 6),
                      SaveCategoryFilterButton(
                        key: const ValueKey('category_btn_live'),
                        label: '实况',
                        hasItems: hasLive,
                        isSelected: _isAllSelected(MediaType.video),
                        onTap: () => _toggleCategory(MediaType.video),
                      ),
                      const SizedBox(width: 6),
                      SaveCategoryFilterButton(
                        key: const ValueKey('category_btn_audio'),
                        label: '音频',
                        hasItems: hasAudio,
                        isSelected: _isAllSelected(MediaType.audio),
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
                    itemBuilder: (context, index) => _buildTile(index),
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