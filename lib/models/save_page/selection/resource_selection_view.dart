import '../../common/work_type.dart';

/// 只读资源视图：图片 / 实况 / 音频
abstract interface class ResourceSelectionView {
  String get key;

  MediaType get type;

  bool get selected;
}
