part of '../save_selection_session.dart';

/// 作品节点契约：视频作品与图文作品共用只读视图，写入只允许会话命令调用。
abstract class _WorkNode implements WorkSelectionView {
  _WorkNode({required this.work, required this.defaultSelected});

  @override
  SaveWorkItem work;

  /// 再次解析时新资源的默认选中值
  final bool defaultSelected;

  @override
  String get url => work.url;

  @override
  bool get isVideo => work.isVideo;

  @override
  List<ResourceSelectionView> get resources;

  @override
  List<MediaItem> get tiers;

  List<_ResourceNode> get resourceNodes;

  @override
  int get tierCount => tiers.length;

  @override
  int get selectedResourceCount => behavesAsVideo
      ? (selection.isSelected ? 1 : 0)
      : resourceNodes.where((resource) => resource.selected).length;

  @override
  int get totalResourceCount =>
      behavesAsVideo ? 1 : resourceNodes.length;

  /// 写入选择；返回「是否发生变化」
  bool applySelection(SelectionState target);

  /// 写入画质偏好；图文作品返回 false
  bool applyQuality(QualityPreference preference);

  /// 物化解析结果；返回「是否发生变化」
  bool ingest(SingleWorkResult parsed);

  /// 资源变化后重算自身聚合；返回「是否发生变化」
  bool refreshSelection();

  List<MediaItem> get selectedItems;
}
