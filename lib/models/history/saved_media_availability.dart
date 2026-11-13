import '../common/work_type.dart';

/// 某条历史记录在一种媒体类型下的本地保存扫描结果
class SavedMediaAvailability {
  const SavedMediaAvailability({
    required this.type,
    required this.found,
    this.count = 0,
    this.contentUri,
    this.folderUri,
    this.displayPath = '',
  });

  /// 媒体类型
  final MediaType type;

  /// 是否找到对应资源
  final bool found;

  /// 找到的文件数量
  final int count;

  /// 最新文件的 content URI
  final String? contentUri;

  /// 文件所在文件夹的目录 URI（用于跳转文件管理器）
  final String? folderUri;

  /// 展示用路径
  final String displayPath;

  bool get available =>
      found && contentUri != null && contentUri!.trim().isNotEmpty;

  factory SavedMediaAvailability.fromMap(Map<String, dynamic> map) {
    final rawType = map['type']?.toString().toLowerCase() ?? '';
    final type = MediaType.values.firstWhere(
      (item) => item.name == rawType,
      orElse: () => MediaType.video,
    );
    return SavedMediaAvailability(
      type: type,
      found: map['found'] == true,
      count: (map['count'] as num?)?.toInt() ?? 0,
      contentUri: map['uri']?.toString(),
      folderUri: map['folderUri']?.toString(),
      displayPath: map['displayPath']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toMap() => {
        'type': type.name,
        'found': found,
        'count': count,
        'uri': contentUri,
        'folderUri': folderUri,
        'displayPath': displayPath,
      };
}

/// 向原生查询某类资源是否存在的请求
class SavedMediaQuery {
  const SavedMediaQuery({
    required this.mediaType,
    this.treeUri,
    this.relativePath,
    this.subDirNames = const [],
    this.namePrefix,
    this.collection = 'auto',
    this.displayPath = '',
  });

  final MediaType mediaType;
  final String? treeUri;

  /// MediaStore 相对路径（不带前导 /）
  final String? relativePath;

  /// SAF 下逐级目录
  final List<String> subDirNames;

  /// 文件名前缀；为 null 时统计目录内全部类型文件
  final String? namePrefix;

  /// auto | downloads
  final String collection;

  final String displayPath;

  Map<String, dynamic> toMap() => {
        'type': mediaType.name,
        'treeUri': treeUri,
        'relativePath': relativePath,
        'subDirNames': subDirNames,
        'namePrefix': namePrefix,
        'collection': collection,
        'displayPath': displayPath,
      };
}
