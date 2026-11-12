import '../common/batch_video_quality.dart';
import 'save_work_item.dart';

/// 中层保存页确认/返回后的结果
class MultiWorkSelectionResult {
  const MultiWorkSelectionResult({
    required this.selectedWorks,
    required this.qualityMode,
    this.allWorks = const [],
  });

  /// 已选中的作品列表（包含全选与部分选择）
  final List<SaveWorkItem> selectedWorks;

  /// 本次面板中的全部作品（含未选与部分选择，用于上层缓存与状态恢复）
  final List<SaveWorkItem> allWorks;

  /// 中层聚合后的视频画质偏好
  final BatchVideoQualityMode qualityMode;
}
