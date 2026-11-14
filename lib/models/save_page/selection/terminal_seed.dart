import '../../common/batch_video_quality.dart';
import '../../common/work_type.dart';
import 'aggregate_state.dart';

/// Terminal 初始化种子：唯一一份记忆的 5 个值
class TerminalSeed {
  const TerminalSeed({
    this.picture = AggregateState.all,
    this.live = AggregateState.all,
    this.music = AggregateState.all,
    this.video = AggregateState.all,
    this.quality = BatchVideoQualityMode.highest,
  });

  final AggregateState picture;

  final AggregateState live;

  final AggregateState music;

  /// 视频作品（work_video）默认是否选中
  final AggregateState video;

  final BatchVideoQualityMode quality;

  bool get videoSelected => video == AggregateState.all;

  bool get qualityLowest => quality == BatchVideoQualityMode.lowest;

  /// 资源类型对应的模板值；只可能是 all / none
  AggregateState intentOf(MediaType type) {
    switch (type) {
      case MediaType.image:
        return picture;
      case MediaType.video:
        return live;
      case MediaType.audio:
        return music;
    }
  }

  bool selectedFor(MediaType type) => intentOf(type) == AggregateState.all;
}