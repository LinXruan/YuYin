import 'file_name_formatter.dart';

/// 作者昵称到文件夹名的安全转换
class AuthorFolderName {
  AuthorFolderName._();

  /// 清洗非法字符、折叠空白并限制长度；昵称为空时回退到 secUid 后 6 位
  static String resolve(String nickname, String secUid, {int maxLength = 40}) {
    final sanitized = FileNameFormatter.sanitize(nickname);
    final collapsed = sanitized.split(RegExp('[ ]+')).where((part) => part.isNotEmpty).join(' ');
    var name = collapsed.trim();

    if (name.length > maxLength) {
      name = name.substring(0, maxLength).trim();
    }
    if (name.isNotEmpty) return name;

    final sec = secUid.trim();
    if (sec.isNotEmpty) {
      final tail = sec.length <= 6 ? sec : sec.substring(sec.length - 6);
      return '作者_$tail';
    }
    return '未知作者';
  }
}
