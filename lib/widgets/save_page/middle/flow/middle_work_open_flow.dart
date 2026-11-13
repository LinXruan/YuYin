part of '../../middle_multi_work_sheet.dart';

// ignore_for_file: unnecessary_this

/// middle work open flow
extension _SheetMiddleWorkOpenFlowFlow on _MiddleMultiWorkSheetState {
  Future<void> _handleOpenWork(int index) async {
    final callback = widget.onOpenWork;
    if (callback == null || _openingIndex != null) return;
    _refresh(() => _openingIndex = index);
    try {
      final result = await callback(_works[index], index);
      if (!mounted || result == null) return;
      _refresh(() {
        final current = _works[index];
        var updated = SaveSelectionTree.applyBottomSelection(
          current,
          result.selectedResources,
          result.parsedResult,
        ).copyWith(
          selectionState: result.state,
          qualityChoice: result.qualityChoice ?? current.qualityChoice,
        );
        final parsedCover = result.parsedResult?.coverUrl?.trim() ?? '';
        if (updated.coverUrl.trim().isEmpty && parsedCover.isNotEmpty) {
          updated = updated.copyWith(coverUrl: parsedCover);
        }
        _works[index] = updated;
        _recomputeQualityMode();
      });
      _publishDebugState();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)
            ?.showSnackBar(SnackBar(content: Text('打开作品失败：$e')));
      }
    } finally {
      if (mounted) _refresh(() => _openingIndex = null);
    }
  }
}
