import '../../../models/media_item.dart';

class ResourceNode implements ResourceSelectionView {
  ResourceNode({
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