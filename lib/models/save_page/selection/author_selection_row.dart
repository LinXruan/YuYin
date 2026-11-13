import '../../user_home/user_home_profile.dart';

/// 选择矩阵中的作者行：只保存作品 URL 引用，作品行本身在矩阵里唯一存在
class AuthorSelectionRow {
  AuthorSelectionRow({
    required this.profile,
    required this.workUrls,
  });

  final UserHomeProfile profile;

  final List<String> workUrls;

  String get secUid => profile.secUid.trim();
}
