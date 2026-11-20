import 'file_name_formatter.dart';

/// 作者昵称到文件夹名的安全转换
class AuthorFolderName {
  AuthorFolderName._();

  /// 清洗非法字符、折叠空白并限制长度；昵称为空时回退到 secUid 后 6 位
  static String resolve(String nickname, String secUid, {int maxLength = 40}) {
    final sanitized = FileNameFormatter.sanitize(nickname);
    final collapsed = sanitized
        .split(RegExp('[ ]+'))
        .where((part) => part.isNotEmpty)
        .join(' ');
    final name = truncateByRunes(collapsed.trim(), maxLength);

    if (name.isNotEmpty) return name;

    final sec = secUid.trim();
    if (sec.isNotEmpty) {
      final tail = sec.length <= 6 ? sec : sec.substring(sec.length - 6);
      return '作者_$tail';
    }
    return '未知作者';
  }

  /// 按 Unicode 码点截断，避免劈裂 Emoji 等 UTF-16 代理对
  static String truncateByRunes(String text, int maxLength) {
    if (maxLength <= 0) return '';
    final runes = text.runes.toList();
    final clipped = runes.length <= maxLength
        ? text
        : String.fromCharCodes(runes.take(maxLength));
    // 截断后可能以空格或点结尾，SAF 与文件系统均不友好
    return clipped.replaceAll(RegExp(r'[ .]+$'), '');
  }
}
