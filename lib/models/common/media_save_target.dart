import 'work_type.dart';

/// MediaStore 集合选择
enum MediaSaveCollection {
  /// 系统 Video / Images / Audio 集合（单作品默认行为）
  auto,

  /// MediaStore.Downloads 集合（主页 Download 目录）
  downloads,
}

/// 单个文件的具体落盘目标
class MediaSaveTarget {
  const MediaSaveTarget({
    this.treeUri,
    this.relativePath,
    this.subDirNames = const [],
    this.collection = MediaSaveCollection.auto,
  });

  /// 自定义 SAF 根目录
  final String? treeUri;

  /// MediaStore 相对路径，不带前导斜杠，如 Download/YuYin/小明/Movies/
  final String? relativePath;

  /// SAF 下需要逐级创建的子目录
  final List<String> subDirNames;

  /// MediaStore 集合
  final MediaSaveCollection collection;

  String get collectionName => collection.name;

  bool get isSaf => treeUri != null && treeUri!.trim().isNotEmpty;
}

typedef MediaSaveTargetResolver = MediaSaveTarget Function(MediaType type);
