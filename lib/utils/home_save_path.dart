import '../models/common/media_save_target.dart';
import '../models/common/work_type.dart';
import 'save_location_store.dart';

/// 主页链接（顶层保存）路径构建：作者目录 + 分类目录
class HomeSavePath {
  HomeSavePath._();

  /// 构建某个作者、某种媒体类型的落盘目标
  static MediaSaveTarget buildTarget(
    SaveLocationConfig config,
    MediaType type,
    String authorFolder,
  ) {
    final treeUri = config.getHomeTreeUri(type);
    final category = categoryFor(type);

    if (treeUri != null && treeUri.trim().isNotEmpty) {
      return MediaSaveTarget(
        treeUri: treeUri,
        subDirNames: [authorFolder, category],
        collection: MediaSaveCollection.downloads,
      );
    }

    final base = relativeBase(config.getHomeDisplayPath(type));
    return MediaSaveTarget(
      relativePath: '$base$authorFolder/$category/',
      collection: MediaSaveCollection.downloads,
    );
  }

  /// 构建展示用路径
  static String buildDisplayPath(
    SaveLocationConfig config,
    MediaType type,
    String authorFolder,
  ) {
    final base = normalizeDisplayBase(config.getHomeDisplayPath(type));
    return '$base$authorFolder/${categoryFor(type)}/';
  }

  /// 媒体类型对应的分类目录
  static String categoryFor(MediaType type) {
    switch (type) {
      case MediaType.video:
        return 'Movies';
      case MediaType.image:
        return 'Pictures';
      case MediaType.audio:
        return 'Music';
    }
  }

  /// 显示基路径规范化为以 / 开头、以 / 结尾
  static String normalizeDisplayBase(String raw) {
    var path = raw.trim();
    if (path.isEmpty) path = SaveLocationConfig.defaultHomeBaseDir;
    if (!path.startsWith('/')) path = '/$path';
    if (!path.endsWith('/')) path = '$path/';
    return path;
  }

  /// MediaStore 相对路径：去掉前导 /，保留结尾 /
  static String relativeBase(String raw) {
    var path = normalizeDisplayBase(raw);
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    return path;
  }
}
