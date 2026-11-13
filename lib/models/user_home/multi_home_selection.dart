import '../common/batch_video_quality.dart';
import '../save_page/save_work_item.dart';
import 'user_home_profile.dart';

export '../common/batch_video_quality.dart';

/// 顶层（多主页）保存页中单个作者的选择状态
enum AuthorSelectionState {
  /// 未选择该作者（无边框）
  none,

  /// 部分选择该作者的作品（虚线框接口）
  partial,

  /// 全选该作者（实线主色边框）
  all,
}

/// 顶层保存页中的单个作者条目
class MultiHomeAuthorItem {
  const MultiHomeAuthorItem({
    required this.profile,
    this.worksTotalTag = 0,
    this.selectionState = AuthorSelectionState.all,
    this.selectedWorkCount = 0,
  });

  /// 作者基础信息（头像与昵称）
  final UserHomeProfile profile;

  /// 作品总数 Tag 标注
  final int worksTotalTag;

  /// 当前选择状态（全选/部分选/未选）
  final AuthorSelectionState selectionState;

  /// 预留字段：中层页面已选作品数量
  final int selectedWorkCount;

  MultiHomeAuthorItem copyWith({
    UserHomeProfile? profile,
    int? worksTotalTag,
    AuthorSelectionState? selectionState,
    int? selectedWorkCount,
  }) {
    return MultiHomeAuthorItem(
      profile: profile ?? this.profile,
      worksTotalTag: worksTotalTag ?? this.worksTotalTag,
      selectionState: selectionState ?? this.selectionState,
      selectedWorkCount: selectedWorkCount ?? this.selectedWorkCount,
    );
  }
}

/// 顶层保存页确认后的返回结果（供后续中层/下载链路接入）
class MultiHomeSelectionResult {
  const MultiHomeSelectionResult({
    required this.selectedAuthors,
    required this.qualityMode,
    this.worksBySecUid = const {},
  });

  /// 已选中的作者列表（包含全选与部分选择）
  final List<MultiHomeAuthorItem> selectedAuthors;

  /// 用户选择的视频保存画质偏好
  final BatchVideoQualityMode qualityMode;

  /// 所有作者的最新作品选择树（保存时唯一数据源）
  final Map<String, List<SaveWorkItem>> worksBySecUid;
}
