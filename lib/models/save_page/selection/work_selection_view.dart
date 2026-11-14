import '../../common/work_type.dart';
import '../../single_work/media_download_item.dart';
import '../save_work_item.dart';
import 'aggregate_state.dart';
import 'quality_indicator.dart';
import 'resource_selection_view.dart';
import 'selection_state.dart';

/// 只读作品视图：视频作品与图文作品共用
abstract interface class WorkSelectionView {
  SaveWorkItem get work;

  String get url;

  /// 作品原始类型（视频 / 图文）
  bool get isVideo;

  /// 当前是否按视频档位处理；视频作品解析出 0 档位时降级为 false
  bool get behavesAsVideo;

  bool get parsed;

  SelectionState get selection;

  /// 视频画质显示态；图文恒为 none
  QualityIndicator get quality;

  int get tierCount;

  List<MediaItem> get tiers;

  MediaItem? get selectedTier;

  List<ResourceSelectionView> get resources;

  /// 某一资源类型的 4 态聚合；视频作品恒为空
  AggregateState resourceState(MediaType type);

  int get selectedResourceCount;

  int get totalResourceCount;
}
