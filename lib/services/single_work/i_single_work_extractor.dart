import '../../models/single_work/single_work_result.dart';

/// 单作品解析与具体资源抓取接口规范
/// 包含：
/// 1. 链接识别与提取 (extractShareUrl)
/// 2. 作品基础信息抓取 (作品名称/标题 + 作品封面)
/// 3. 具体资源直链抓取 (多清晰度视频、无水印图集、实况 LivePhoto、背景音频)
abstract class ISingleWorkExtractor {
  /// 从包含抖音作品的文本中提取并规范化作品链接
  String? extractShareUrl(String text);

  /// 单链接具体资源解析与直链抓取接口
  /// 返回包含：
  /// - 作品名称/标题 (title / desc)
  /// - 作品封面 (coverUrl)
  /// - 具体资源直链列表 (videoItems, imageItems, audioItems)
  Future<SingleWorkResult> extract(String shareUrl);

  /// 取消当前正在执行的单作品解析任务
  void cancel();
}
