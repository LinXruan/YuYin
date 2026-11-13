import '../common/batch_video_quality.dart';
import 'save_work_item.dart';

/// 顶层进入中层后返回的该作者完整选择结果
class AuthorWorksSelection {
  const AuthorWorksSelection({
    required this.works,
    required this.qualityMode,
  });

  /// 该作者全部作品的最新状态
  final List<SaveWorkItem> works;

  /// 该作者视频作品的聚合画质
  final BatchVideoQualityMode qualityMode;
}
