import '../common/work_type.dart';

/// 单个作者的批量保存结果
class UserHomeAuthorSaveResult {
  const UserHomeAuthorSaveResult({
    required this.secUid,
    required this.nickname,
    required this.success,
    this.savedCounts = const {},
    this.failedCount = 0,
    this.error,
  });

  final String secUid;
  final String nickname;
  final bool success;

  /// 各媒体类型成功保存数量
  final Map<MediaType, int> savedCounts;

  /// 失败作品数量
  final int failedCount;

  final String? error;
}

/// 顶层多作者批量保存结果
class UserHomeBatchSaveResult {
  const UserHomeBatchSaveResult({required this.authors});

  final List<UserHomeAuthorSaveResult> authors;

  int get totalSaved => authors.fold(
        0,
        (sum, author) => sum + author.savedCounts.values.fold(0, (a, b) => a + b),
      );

  int get failedAuthors => authors.where((author) => !author.success).length;
}
