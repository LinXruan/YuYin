import '../../media_item.dart';

/// 保存时的一个确定作品：资源列表与画质已由矩阵解算完毕
class SelectedWork {
  const SelectedWork({
    required this.work,
    required this.parsed,
    required this.items,
    this.quality,
  });

  final SaveWorkItem work;

  final SingleWorkResult parsed;

  /// 精确要落盘的资源（视频为单档位）
  final List<MediaItem> items;

  /// 视频作品的档位选择；图文作品为 null
  final WorkVideoQualityChoice? quality;
}