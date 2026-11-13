import '../../models/media_item.dart';

/// 保存页中的单个作品条目
///
/// 只承载作品元数据；选择状态与画质由 [SelectionMatrix] 唯一维护。
class SaveWorkItem {
  const SaveWorkItem({
    required this.url,
    required this.kind,
    this.title = '',
    this.coverUrl = '',
    this.parsedResult,
  });

  /// 作品页面链接
  final String url;

  /// 作品类型（视频 / 图文；文章不会进入保存页）
  final WorkMediaKind kind;

  /// 作品标题/文案
  final String title;

  /// 作品封面网络直链
  final String coverUrl;

  /// 已解析的完整资源（主页来源首次进入底层前为空）
  final SingleWorkResult? parsedResult;

  bool get isVideo => kind == WorkMediaKind.video;

  SaveWorkItem copyWith({
    String? url,
    WorkMediaKind? kind,
    String? title,
    String? coverUrl,
    SingleWorkResult? parsedResult,
  }) {
    return SaveWorkItem(
      url: url ?? this.url,
      kind: kind ?? this.kind,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      parsedResult: parsedResult ?? this.parsedResult,
    );
  }
}
