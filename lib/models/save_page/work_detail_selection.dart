import '../single_work/media_download_item.dart';
import '../single_work/single_work_result.dart';
import 'work_selection_state.dart';
import 'work_video_quality_choice.dart';

/// 中层进入底层后返回的选择结果
class WorkDetailSelection {
  const WorkDetailSelection({
    required this.state,
    this.selectedResources = const [],
    this.qualityChoice,
    this.parsedResult,
  });

  /// 该作品的选择状态（全选 / 部分 / 未选）
  final WorkSelectionState state;

  /// 已选资源列表（图文/实况/音频作品）
  final List<MediaItem> selectedResources;

  /// 视频作品选择的画质档位
  final WorkVideoQualityChoice? qualityChoice;

  /// 底层解析得到的完整结果（用于回填封面与缓存）
  final SingleWorkResult? parsedResult;
}
