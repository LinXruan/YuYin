import '../../user_home/user_home_profile.dart';
import 'quality_indicator.dart';
import 'selection_state.dart';
import 'work_selection_view.dart';

/// 只读作者视图：真实作者或 multi/single 的隐藏虚拟作者
abstract interface class AuthorSelectionView {
  String get secUid;

  UserHomeProfile get profile;

  bool get synthetic;

  SelectionState get selection;

  QualityIndicator get quality;

  int get totalWorks;

  int get selectedWorks;

  List<WorkSelectionView> get works;
}
