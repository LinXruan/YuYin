import '../../models/common/batch_video_quality.dart';
import '../../models/common/work_type.dart';
import '../../models/save_page/selection/selection_cell.dart';
import '../../models/save_page/selection/work_selection_row.dart';
import '../../models/single_work/single_work_result.dart';

/// 解析结果 -> 矩阵单元
///
/// 重复调用必须保留用户已有选择，只追加新出现的资源。
class SelectionIngest {
  SelectionIngest._();

  static void apply(
    WorkSelectionRow row,
    SingleWorkResult parsed, {
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    final hadCells = row.cells.isNotEmpty;
    final previous = {for (final cell in row.cells) cell.key: cell.value};
    row.parsed = true;

    if (row.isVideo) {
      row.tierCount = parsed.videoItems.length;
      final fallback = row.defaultSelected ? 1 : 0;
      final initial = hadCells
          ? previous.values.first
          : ((row.preferLowest || quality == BatchVideoQualityMode.lowest) &&
                  row.tierCount > 0
              ? row.tierCount
              : fallback);
      row.cells
        ..clear()
        ..add(
          SelectionCell(
            key: row.work.url,
            type: MediaType.video,
            value: _clampTier(initial, row.tierCount),
          ),
        );
      return;
    }

    row.tierCount = 0;
    row.cells
      ..clear()
      ..addAll(
        parsed.items.map(
          (item) => SelectionCell(
            key: item.url,
            type: item.type,
            value: previous[item.url] ?? (row.defaultSelected ? 1 : 0),
          ),
        ),
      );
  }

  static int _clampTier(int value, int tierCount) {
    if (value <= 0) return 0;
    if (tierCount <= 0) return 1;
    return value > tierCount ? tierCount : value;
  }
}