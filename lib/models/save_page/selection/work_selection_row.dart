import '../../media_item.dart';

/// 选择矩阵中的作品行
class WorkSelectionRow {
  WorkSelectionRow({
    required this.work,
    required this.defaultSelected,
    this.tierCount = 0,
    this.preferLowest = false,
    this.parsed = false,
    List<SelectionCell>? cells,
  }) : cells = cells ?? <SelectionCell>[];

  /// 作品元数据（封面/标题可能在解析后回填）
  SaveWorkItem work;

  /// 该作品的全部选择单元：视频恒 1 个，图文为 N 个
  final List<SelectionCell> cells;

  /// 是否已解析出资源构成
  bool parsed;

  /// 解析前的默认选择（记忆决定，可被上层操作改写）
  bool defaultSelected;

  /// 视频档位数量（非视频为 0）
  int tierCount;

  /// 未解析视频的档位偏好：解析后据此初始化
  bool preferLowest;

  String get url => work.url;

  bool get isVideo => work.isVideo;

  /// 保存时使用的资源列表：完全由 cell 决定，不存在「空 = 全部」
  List<MediaItem> get selectedItems {
    final parsedResult = work.parsedResult;
    if (!parsed || parsedResult == null) return const [];
    if (isVideo) {
      final cell = cells.isEmpty ? null : cells.first;
      if (cell == null || cell.value <= 0) return const [];
      final tiers = parsedResult.videoItems;
      if (tiers.isEmpty) return const [];
      final index = (cell.value - 1).clamp(0, tiers.length - 1);
      return [tiers[index]];
    }
    final byUrl = {for (final item in parsedResult.items) item.url: item};
    return [
      for (final cell in cells)
        if (cell.isSelected && byUrl.containsKey(cell.key)) byUrl[cell.key]!,
    ];
  }
}