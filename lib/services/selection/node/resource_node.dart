import '../../../models/common/work_type.dart';
import '../../../models/save_page/selection/resource_selection_view.dart';

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