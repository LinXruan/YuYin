/// 单条历史解析记录数据模型
class HistoryItem {
  HistoryItem({
    required this.id,
    required this.url,
    this.rawInput = '',
    required this.fullDesc,
    this.title,
    String? coverUrl,
    this.isImagePost = false,
    this.mediaSummary = '',
    this.itemCount = 1,
    DateTime? createdAt,
  })  : coverUrl = (coverUrl != null && !isVideoUrl(coverUrl)) ? coverUrl : null,
        createdAt = createdAt ?? DateTime.now();

  /// 记录唯一标识（通常为作品短链或原始链接）
  final String id;

  /// 用于重新填入解析输入框的有效链接
  final String url;

  /// 用户最初粘贴的原始文本或口令
  final String rawInput;

  /// 作品完整文案描述（不受界面截断影响，用于全文模糊搜索）
  final String fullDesc;

  /// 作品标题（可能为空）
  final String? title;

  /// 封面缩略图网络地址
  final String? coverUrl;

  /// 是否为图文/实况作品（true=图文，false=纯视频）
  final bool isImagePost;

  /// 媒体类型摘要（如“图集/音频/文案”或“视频/文案”）
  final String mediaSummary;

  /// 包含的资源总数
  final int itemCount;

  /// 解析成功的时间戳
  final DateTime createdAt;

  /// 人性化相对/绝对时间展示（严格不显示“抖音”两个字）
  String get formattedTime {
    final now = DateTime.now();
    final local = createdAt.toLocal();
    final isToday = local.year == now.year &&
        local.month == now.month &&
        local.day == now.day;

    final hourStr = local.hour.toString().padLeft(2, '0');
    final minuteStr = local.minute.toString().padLeft(2, '0');
    final timeStr = '$hourStr:$minuteStr';

    if (isToday) {
      return '今天 $timeStr';
    }

    final yesterday = now.subtract(const Duration(days: 1));
    final isYesterday = local.year == yesterday.year &&
        local.month == yesterday.month &&
        local.day == yesterday.day;
    if (isYesterday) {
      return '昨天 $timeStr';
    }

    final monthStr = local.month.toString().padLeft(2, '0');
    final dayStr = local.day.toString().padLeft(2, '0');
    if (local.year == now.year) {
      return '$monthStr-$dayStr $timeStr';
    }

    return '${local.year}-$monthStr-$dayStr $timeStr';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'rawInput': rawInput,
        'fullDesc': fullDesc,
        if (title != null) 'title': title,
        if (coverUrl != null) 'coverUrl': coverUrl,
        'isImagePost': isImagePost,
        'mediaSummary': mediaSummary,
        'itemCount': itemCount,
        'createdAt': createdAt.toIso8601String(),
      };

  /// 判断一个 URL 是否为纯视频流链接（严禁作为封面缩略图）
  static bool isVideoUrl(String? url) {
    if (url == null || url.trim().isEmpty) return false;
    final lower = url.trim().toLowerCase();
    return lower.contains('.mp4') ||
        lower.contains('.mov') ||
        lower.contains('.flv') ||
        lower.contains('.m3u8') ||
        lower.contains('video_id=') ||
        lower.contains('/aweme/v1/play') ||
        lower.contains('/playwm/');
  }

  factory HistoryItem.fromJson(Map<String, dynamic> json) {
    return HistoryItem(
      id: json['id']?.toString() ?? '',
      url: json['url']?.toString() ?? '',
      rawInput: json['rawInput']?.toString() ?? '',
      fullDesc: json['fullDesc']?.toString() ?? '',
      title: json['title']?.toString(),
      coverUrl: json['coverUrl']?.toString(),
      isImagePost: json['isImagePost'] == true,
      mediaSummary: json['mediaSummary']?.toString() ?? '文案',
      itemCount: (json['itemCount'] as num?)?.toInt() ?? 0,
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }
}
