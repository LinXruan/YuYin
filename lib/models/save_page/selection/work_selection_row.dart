import '../../media_item.dart';

/// 选择矩阵中的作品行：作品 → 资源类型 → 资源单元
class WorkSelectionRow {
  WorkSelectionRow({
    required this.work,
    required this.defaultSelected,
    this.tierCount = 0,
    this.preferLowest = false,
    this.parsed = false,
    Map<MediaType, SelectionGroup>? groups,
  }) : groups = groups ?? <MediaType, SelectionGroup>{} {
    if (isVideo && !this.groups.containsKey(MediaType.video)) {
      this.groups[MediaType.video] = SelectionGroup(
        type: MediaType.video,
        cells: [
          SelectionCell(
            key: work.url,
            type: MediaType.video,
            value: defaultSelected ? 1 : 0,
          ),
        ],
      );
    }
  }

  /// 作品元数据
  SaveWorkItem work;

  /// 资源类型维度
  final Map<MediaType, SelectionGroup> groups;

  /// 是否已解析出资源构成
  bool parsed;

  /// 解析前的默认选择（可被上层操作改写）
  bool defaultSelected;

  /// 视频档位数量（非视频为 0）
  int tierCount;

  /// 未解析视频的档位偏好
  bool preferLowest;

  String get url => work.url;

  bool get isVideo => work.isVideo;

  /// 展平后的全部单元
  Iterable<SelectionCell> get allCells =>
      groups.values.expand((group) => group.cells);

  List<SelectionCell> cellsOf(MediaType type) =>
      groups[type]?.cells ?? const <SelectionCell>[];

  List<SelectionCell> get videoCells => cellsOf(MediaType.video);

  /// 视频作品的唯一档位载体
  SelectionCell? get videoCell =>
      isVideo && videoCells.isNotEmpty ? videoCells.first : null;

  /// 0 = 未选；1..n = 档位序号
  int get videoValue => videoCell?.value ?? 0;

  /// 当前画质档位（未选返回 none）
  QualityIndicator get qualityLevel {
    if (!isVideo) return QualityIndicator.none;
    if (videoValue <= 0) return QualityIndicator.none;
    if (!parsed) {
      return preferLowest ? QualityIndicator.lowest : QualityIndicator.highest;
    }
    if (videoValue == 1) return QualityIndicator.highest;
    if (tierCount > 0 && videoValue >= tierCount) {
      return QualityIndicator.lowest;
    }
    return QualityIndicator.mixed;
  }

  /// 保存时使用的资源列表：完全由单元决定
  List<MediaItem> get selectedItems {
    final parsedResult = work.parsedResult;
    if (!parsed || parsedResult == null) return const [];
    if (isVideo) {
      final cell = videoCell;
      if (cell == null || cell.value <= 0) return const [];
      final tiers = parsedResult.videoItems;
      if (tiers.isEmpty) return const [];
      final index = (cell.value - 1).clamp(0, tiers.length - 1);
      return [tiers[index]];
    }
    final byUrl = {for (final item in parsedResult.items) item.url: item};
    return [
      for (final cell in allCells)
        if (cell.isSelected && byUrl.containsKey(cell.key)) byUrl[cell.key]!,
    ];
  }
}
