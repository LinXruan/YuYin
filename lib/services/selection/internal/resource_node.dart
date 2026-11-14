part of '../save_selection_session.dart';

class _ResourceNode implements ResourceSelectionView {
  _ResourceNode({
    required this.key,
    required this.type,
    required this.selected,
  });

  @override
  final String key;

  @override
  final MediaType type;

  @override
  bool selected;
}
