import '../../user_home/user_home_profile.dart';
import 'aggregate_state.dart';
import 'quality_indicator.dart';
import 'work_selection_view.dart';

/// 只读作者视图：真实作者或 multi/single 的隐藏虚拟作者
///
/// 7 个维度：选择、画质，以及图片 / 实况 / 音频 / 图文 / 视频聚合。
abstract interface class AuthorSelectionView {
  String get secUid;

  UserHomeProfile get profile;

  bool get synthetic;

  AggregateState get selection;

  QualityIndicator get quality;

  AggregateState get picture;

  AggregateState get live;

  AggregateState get music;

  AggregateState get noteSelection;

  AggregateState get videoSelection;

  int get totalWorks;

  int get selectedWorks;

  List<WorkSelectionView> get works;
}
