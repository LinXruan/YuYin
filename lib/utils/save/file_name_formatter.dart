import '../../models/media_item.dart';

/// 资源自动命名与格式化工具类
class FileNameFormatter {
  FileNameFormatter._();

  /// 操作系统文件名非法字符（Windows / Android / Linux / macOS）
  static final RegExp _illegalChars = RegExp(r'[/\\:*?"<>|\x00-\x1f]');

  /// 多个连续空白字符
  static final RegExp _multipleWhitespace = RegExp(r'\s+');

  /// 清洗文本，移除文件名非法字符，折叠空白
  static String sanitize(String text) {
    var cleaned = text.replaceAll(_illegalChars, ' ');
    cleaned = cleaned.replaceAll(_multipleWhitespace, ' ');
    // 移除收尾空格以及 Windows 文件名不允许的收尾句号
    cleaned = cleaned.trim();
    while (cleaned.endsWith('.')) {
      cleaned = cleaned.substring(0, cleaned.length - 1).trim();
    }
    return cleaned;
  }

  /// 按照中文字符上限（10 个汉字或 20 个 ASCII 显示宽度）截断文本，超出部分附加省略号 "..."
  ///
  /// 权重规则：
  /// - CJK 汉字、全角字符、Emoji 等多字节字符计为 1.0 权重；
  /// - ASCII 半角字符、数字、标点计为 0.5 权重；
  /// - 默认 [maxWeight] = 10.0（等价 10 个中文字符或 20 个英文半角字符）。
  static String truncate(String text, {double maxWeight = 10.0}) {
    if (text.isEmpty) return '';

    final runes = text.runes.toList();
    var currentWeight = 0.0;
    var cutIndex = 0;
    var needTruncate = false;

    for (var i = 0; i < runes.length; i++) {
      final codePoint = runes[i];
      // ASCII 字符权重 0.5，其余字符（汉字、标点、Emoji）权重 1.0
      final weight = codePoint <= 0x7F ? 0.5 : 1.0;
      if (currentWeight + weight > maxWeight) {
        needTruncate = true;
        cutIndex = i;
        break;
      }
      currentWeight += weight;
    }

    if (!needTruncate) {
      return text;
    }

    final truncatedRunes = runes.sublist(0, cutIndex);
    var result = String.fromCharCodes(truncatedRunes).trim();
    while (result.endsWith('.')) {
      result = result.substring(0, result.length - 1).trim();
    }
    return '$result...';
  }

  /// 计算基础文件名（已完成清洗、截断与保底策略）
  static String buildBaseName(String? rawTitleOrDesc, {int? fallbackTimestamp}) {
    if (rawTitleOrDesc != null && rawTitleOrDesc.trim().isNotEmpty) {
      final sanitized = sanitize(rawTitleOrDesc);
      if (sanitized.isNotEmpty) {
        final truncated = truncate(sanitized);
        if (truncated.isNotEmpty) {
          return truncated;
        }
      }
    }
    final tag = fallbackTimestamp ?? DateTime.now().millisecondsSinceEpoch;
    return 'YuYin_$tag';
  }

  /// 为下载批次中的某一项生成最终文件名
  ///
  /// 规则：
  /// - 选中的资源中，若同类型（如 image / video / audio）总数 > 1，则追加 `_1`, `_2` 后缀；
  /// - 若同类型总数 == 1（即便包含多种不同类型资源），则不追加序号后缀；
  /// - 自动拼接扩展名。
  static String formatFileName({
    required MediaItem item,
    required List<MediaItem> allItems,
    required int currentIndex,
    String? rawTitleOrDesc,
    int? fallbackTimestamp,
    String? extension,
  }) {
    final baseName = buildBaseName(
      rawTitleOrDesc,
      fallbackTimestamp: fallbackTimestamp,
    );

    final sameTypeTotal = allItems.where((it) => it.type == item.type).length;
    final sameTypeIndex = allItems
        .sublist(0, currentIndex + 1)
        .where((it) => it.type == item.type)
        .length;

    final suffix = sameTypeTotal > 1 ? '_$sameTypeIndex' : '';
    final ext = extension ?? defaultExtensionFor(item);

    return '$baseName$suffix.$ext';
  }

  /// 根据资源类型与链接自动推断合适的文件后缀名
  static String defaultExtensionFor(MediaItem item) {
    if (item.type == MediaType.image) {
      final lower = item.url.toLowerCase();
      if (lower.contains('.png')) return 'png';
      if (lower.contains('.webp')) return 'webp';
      return 'jpg';
    }
    if (item.type == MediaType.audio) {
      final lower = item.url.toLowerCase();
      if (lower.contains('.wav')) return 'wav';
      if (lower.contains('.mp3')) return 'mp3';
      return 'm4a';
    }
    return 'mp4';
  }
}

