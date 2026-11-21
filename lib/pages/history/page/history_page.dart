import 'package:flutter/material.dart';

import '../../../utils/history/history_store.dart';
import '../../../utils/savelocation/save_location_store.dart';
import '../../../utils/thumbnail/history_thumbnail_cache.dart';
import '../flow/search/history_search_coordinator.dart';
import '../flow/selection/history_selection_coordinator.dart';
import '../widget/frame/history_frame.dart';

/// 历史记录页：支持全文模糊检索、多选批量删除、复制链接与一键重新解析
class HistoryPage extends StatefulWidget {
  const HistoryPage({
    super.key,
    this.saveLocationStore,
    this.onRequestParse,
  });

  final SaveLocationStore? saveLocationStore;
  final ValueChanged<String>? onRequestParse;

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage>
    with AutomaticKeepAliveClientMixin {
  late final HistorySelectionCoordinator _selection;
  late final HistorySearchCoordinator _search;

  bool _sessionDismissed = false;
  late bool _permanentlyDismissed = HistoryStore.promptDismissed;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _selection = HistorySelectionCoordinator(
      onChanged: () {
        if (mounted) setState(() {});
      },
    );
    _search = HistorySearchCoordinator(
      onChanged: () {
        if (mounted) setState(() {});
      },
      onFilterSavedChanged: (onlySaved) {
        if (onlySaved) {
          final savedIds = HistoryStore.records
              .where((item) => item.isSaved)
              .map((item) => item.id)
              .toSet();
          _selection.pruneUnsaved(savedIds);
        }
      },
      onTypeFilterChanged: (filter) {
        final validIds = HistoryStore.search(
          _search.searchQuery,
          onlySaved: _search.filterOnlySaved,
          typeFilter: filter,
        ).map((item) => item.id).toSet();
        _selection.pruneDeleted(validIds);
      },
    );
    HistoryThumbnailCache.warmUp();
    HistoryStore.recordsNotifier.addListener(_onRecordsChanged);
    if (!_permanentlyDismissed) {
      HistoryStore.isPromptDismissed().then((dismissed) {
        if (mounted && dismissed) {
          setState(() => _permanentlyDismissed = true);
        }
      });
    }
  }

  @override
  void dispose() {
    HistoryStore.recordsNotifier.removeListener(_onRecordsChanged);
    _search.dispose();
    super.dispose();
  }

  void _onRecordsChanged() {
    if (!mounted) return;
    setState(() {
      final currentIds = HistoryStore.records.map((r) => r.id).toSet();
      _selection.pruneDeleted(currentIds);
    });
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final displayedItems = HistoryStore.search(
      _search.searchQuery,
      onlySaved: _search.filterOnlySaved,
      typeFilter: _search.typeFilter,
    );
    final hasAnyRecord = HistoryStore.records.isNotEmpty;

    return HistoryFrame(
      selection: _selection,
      search: _search,
      displayedItems: displayedItems,
      hasAnyRecord: hasAnyRecord,
      sessionDismissed: _sessionDismissed,
      permanentlyDismissed: _permanentlyDismissed,
      onRequestParse: widget.onRequestParse,
      onDismissSession: () {
        setState(() => _sessionDismissed = true);
      },
      saveLocationStore: widget.saveLocationStore,
      onPermanentlyDismiss: () async {
        setState(() => _permanentlyDismissed = true);
        await HistoryStore.setPromptDismissed(true);
      },
    );
  }
}
