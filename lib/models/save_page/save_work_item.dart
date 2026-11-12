import '../single_work/media_download_item.dart';
import '../single_work/single_work_result.dart';
import 'work_kind.dart';
import 'work_selection_state.dart';
import 'work_video_quality_choice.dart';

/// 中层保存页中的单个作品条目
class SaveWorkItem {
  const SaveWorkItem({
    required this.url,
    required this.kind,
    this.title = '',
    this.coverUrl = '',
    this.selectionState = WorkSelectionState.all,
    this.selectedResources = const [],
    this.qualityChoice = const WorkVideoQualityChoice.highest(),
    this.parsedResult,
  });

  /// 作品页面链接
  final String url;

  /// 作品类型（视频 / 图文；文章不会进入保存页）
  final WorkMediaKind kind;

  /// 作品标题/文案
  final String title;

  /// 作品封面网络直链
  final String coverUrl;

  /// 当前选择状态（全选 / 部分 / 未选）
  final WorkSelectionState selectionState;

  /// 已选资源（用于再次进入底层时恢复勾选）
  final List<MediaItem> selectedResources;

  /// 视频作品的画质选择（图文作品不参与聚合）
  final WorkVideoQualityChoice qualityChoice;

  /// 已解析的单作品完整资源（主页来源首次进入底层前为空）
  final SingleWorkResult? parsedResult;

  bool get isVideo => kind == WorkMediaKind.video;

  /// 已选资源的 URL 集合，便于底层恢复勾选
  Set<String> get selectedResourceUrls =>
      selectedResources.map((item) => item.url).toSet();

  SaveWorkItem copyWith({
    String? url,
    WorkMediaKind? kind,
    String? title,
    String? coverUrl,
    WorkSelectionState? selectionState,
    List<MediaItem>? selectedResources,
    WorkVideoQualityChoice? qualityChoice,
    SingleWorkResult? parsedResult,
  }) {
    return SaveWorkItem(
      url: url ?? this.url,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      selectionState: selectionState ?? this.selectionState,
      selectedResources: selectedResources ?? this.selectedResources,
      qualityChoice: qualityChoice ?? this.qualityChoice,
      parsedResult: parsedResult ?? this.parsedResult,
    );
  }
}
