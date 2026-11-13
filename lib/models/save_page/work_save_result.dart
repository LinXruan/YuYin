import '../common/work_type.dart';

/// 单个作品批量保存结果
class WorkSaveResult {
  const WorkSaveResult({
    required this.url,
    required this.success,
    this.savedTypes = const {},
    this.savedBaseName = '',
    this.error,
  });

  /// 作品链接
  final String url;

  /// 是否至少保存成功一个资源
  final bool success;

  /// 本次成功保存的媒体类型
  final Set<MediaType> savedTypes;

  /// 保存时使用的文件基名
  final String savedBaseName;

  /// 失败原因
  final String? error;
}
