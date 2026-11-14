import '../../models/common/batch_video_quality.dart';
import '../../models/common/work_type.dart';
import '../../models/save_page/selection/selection_cell.dart';
import '../../models/save_page/selection/selection_group.dart';
import '../../models/save_page/selection/work_selection_row.dart';
import '../../models/single_work/single_work_result.dart';

/// 解析结果 -> 按资源类型分组写入矩阵
///
/// 重复调用保留用户已有选择，只追加新出现的资源。
class SelectionIngest {
  SelectionIngest._();

  static void apply(
    WorkSelectionRow row,
    SingleWorkResult parsed, {
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    final previous = {for (final cell in row.allCells) cell.key: cell.value};
    row.parsed = true;

    if (row.isVideo) {
      _applyVideo(row, parsed, previous, quality);
      return;
    }
    _applyMedia(row, parsed, previous);
  }

  static void _applyVideo(
    WorkSelectionRow row,
    SingleWorkResult parsed,
    Map<String, int> previous,
    BatchVideoQualityMode quality,
  ) {
    row.tierCount = parsed.videoItems.length;
    final old = previous[row.work.url] ?? row.videoValue;
    final initial = old > 0
        ? old
        : ((row.preferLowest || quality == BatchVideoQualityMode.lowest) &&
                  row.tierCount > 0
              ? row.tierCount
              : (row.defaultSelected ? 1 : 0));
    final value = initial <= 0
        ? 0
        : (row.tierCount > 0 && initial > row.tierCount
              ? row.tierCount
              : initial);
    row.groups[MediaType.video] = SelectionGroup(
      type: MediaType.video,
      cells: [
        SelectionCell(key: row.work.url, type: MediaType.video, value: value),
      ],
    );
  }

  static void _applyMedia(
    WorkSelectionRow row,
    SingleWorkResult parsed,
    Map<String, int> previous,
  ) {
    row.tierCount = 0;
    final groups = <MediaType, SelectionGroup>{};
    for (final item in parsed.items) {
      final value = previous[item.url] ?? (row.defaultSelected ? 1 : 0);
      groups
          .putIfAbsent(item.type, () => SelectionGroup(type: item.type))
          .cells
          .add(
            SelectionCell(key: item.url, type: item.type, value: value),
          );
    }
    row.groups
      ..clear()
      ..addAll(groups);
  }
}
