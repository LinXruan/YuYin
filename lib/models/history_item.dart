import 'history/history_record_type.dart';

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
    this.isSaved = false,
    this.recordType = HistoryRecordType.work,
    this.authorSecUid,
    this.savedBaseName,
  })  : coverUrl = (coverUrl != null && !isVideoUrl(coverUrl)) ? coverUrl : null,
        createdAt = createdAt ?? DateTime.now();

  /// 记录唯一标识（作品通常为有效链接；主页为 home:secUid）
  final String id;

  /// 用于复制/重新解析的有效链接
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

  /// 媒体类型摘要（如“图集/音频/文案”或“视频/文案”或“作者主页”）
  final String mediaSummary;

  /// 包含的资源总数（主页记录为作品数）
  final int itemCount;

  /// 解析成功的时间戳
  final DateTime createdAt;

  /// 是否已下载保存至本地存储（false=仅解析，true=已保存）
  final bool isSaved;

  /// 记录类型：作品 / 作者主页
  final HistoryRecordType recordType;

  /// 主页记录专用：作者 secUid
  final String? authorSecUid;

  /// 作品记录专用：保存时使用的文件基名
  final String? savedBaseName;

  bool get isUserHome => recordType == HistoryRecordType.userHome;

  /// 卡片主标题
  String get displayTitle {
    if (isUserHome) {
      if (fullDesc.trim().isNotEmpty) return fullDesc.trim();
      if (title?.trim().isNotEmpty == true) return title!.trim();
      return '未知作者';
    }
    if (fullDesc.trim().isNotEmpty) return fullDesc.trim();
    if (title?.trim().isNotEmpty == true) return title!.trim();
    return '无描述';
  }

  /// 卡片副信息
  String get displaySubtitle {
    if (isUserHome) return '作者主页 · $itemCount 个作品';
    return mediaSummary;
  }

  /// 单击复制的内容：主页优先用 secUid 生成规范链接
  String get copyText {
    if (isUserHome) {
      final secUid = authorSecUid?.trim() ?? '';
      if (secUid.isNotEmpty) {
        return 'https://www.douyin.com/user/$secUid';
      }
    }
    if (url.trim().isNotEmpty) return url.trim();
    return rawInput.trim();
  }

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
        'isSaved': isSaved,
        'recordType': recordType.name,
        if (authorSecUid != null) 'authorSecUid': authorSecUid,
        if (savedBaseName != null) 'savedBaseName': savedBaseName,
      };

  HistoryItem copyWith({
    String? id,
    String? url,
    String? rawInput,
    String? fullDesc,
    String? title,
    String? coverUrl,
    bool? isImagePost,
    String? mediaSummary,
    int? itemCount,
    DateTime? createdAt,
    bool? isSaved,
    HistoryRecordType? recordType,
    String? authorSecUid,
    String? savedBaseName,
  }) {
    return HistoryItem(
      id: id ?? this.id,
      url: url ?? this.url,
      rawInput: rawInput ?? this.rawInput,
      fullDesc: fullDesc ?? this.fullDesc,
      title: title ?? this.title,
      coverUrl: coverUrl ?? this.coverUrl,
      isImagePost: isImagePost ?? this.isImagePost,
      mediaSummary: mediaSummary ?? this.mediaSummary,
      itemCount: itemCount ?? this.itemCount,
      createdAt: createdAt ?? this.createdAt,
      isSaved: isSaved ?? this.isSaved,
      recordType: recordType ?? this.recordType,
      authorSecUid: authorSecUid ?? this.authorSecUid,
      savedBaseName: savedBaseName ?? this.savedBaseName,
    );
  }

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
    final rawType = json['recordType']?.toString() ?? '';
    final recordType = HistoryRecordType.values.firstWhere(
      (item) => item.name == rawType,
      orElse: () => HistoryRecordType.work,
    );
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
      isSaved: json['isSaved'] == true,
      recordType: recordType,
      authorSecUid: json['authorSecUid']?.toString(),
      savedBaseName: json['savedBaseName']?.toString(),
    );
  }
}
