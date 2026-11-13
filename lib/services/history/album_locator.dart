import '../../models/history_item.dart';
import '../../models/media_item.dart';
import '../../utils/author_folder_name.dart';
import '../../utils/file_name_formatter.dart';
import '../../utils/home_save_path.dart';
import '../../utils/save_location_store.dart';
import '../media_saver.dart';

/// 历史记录「打开」定位：把记录转换为当前保存路径下的扫描请求
class AlbumLocator {
  AlbumLocator._();

  /// 纯逻辑：生成三类资源的查询请求
  static List<SavedMediaQuery> buildQueries(
    HistoryItem item,
    SaveLocationConfig config,
  ) {
    if (!item.isUserHome && resolveWorkPrefix(item).isEmpty) {
      return const [];
    }

    final queries = <SavedMediaQuery>[];
    for (final type in MediaType.values) {
      if (item.isUserHome) {
        final folder = AuthorFolderName.resolve(
          item.displayTitle,
          item.authorSecUid ?? '',
        );
        final target = HomeSavePath.buildTarget(config, type, folder);
        queries.add(
          SavedMediaQuery(
            mediaType: type,
            treeUri: target.treeUri,
            relativePath: target.relativePath,
            subDirNames: target.subDirNames,
            namePrefix: null,
            collection: target.collectionName,
            displayPath: HomeSavePath.buildDisplayPath(config, type, folder),
          ),
        );
        continue;
      }

      final prefix = resolveWorkPrefix(item);
      final treeUri = config.getTreeUri(type);
      final displayPath = config.getDisplayPath(type);
      if (treeUri != null && treeUri.trim().isNotEmpty) {
        queries.add(
          SavedMediaQuery(
            mediaType: type,
            treeUri: treeUri,
            namePrefix: prefix,
            collection: 'auto',
            displayPath: displayPath,
          ),
        );
      } else {
        queries.add(
          SavedMediaQuery(
            mediaType: type,
            relativePath: relativeSinglePath(displayPath),
            namePrefix: prefix,
            collection: 'auto',
            displayPath: displayPath,
          ),
        );
      }
    }
    return queries;
  }

  /// 扫描当前保存路径；作品记录无法推导基名时直接返回三类缺失
  static Future<List<SavedMediaAvailability>> scan(
    HistoryItem item, {
    SaveLocationConfig? config,
  }) async {
    final currentConfig = config ?? SaveLocationStore.current;
    if (!item.isUserHome && resolveWorkPrefix(item).isEmpty) {
      return [
        for (final type in MediaType.values)
          SavedMediaAvailability(
            type: type,
            found: false,
            displayPath: currentConfig.getDisplayPath(type),
          ),
      ];
    }
    return MediaSaver.querySavedMedia(buildQueries(item, currentConfig));
  }

  /// 优先跳转文件管理器文件夹，失败时打开文件
  static Future<bool> open(SavedMediaAvailability availability) {
    final mimeType = switch (availability.type) {
      MediaType.video => 'video/*',
      MediaType.image => 'image/*',
      MediaType.audio => 'audio/*',
    };
    return MediaSaver.openMediaLocation(
      contentUri: availability.contentUri,
      folderUri: availability.folderUri,
      mimeType: mimeType,
    );
  }

  /// 作品定位基名：优先使用保存时记录的基名，旧记录从文案/标题推导
  static String resolveWorkPrefix(HistoryItem item) {
    final saved = FileNameFormatter.sanitize(item.savedBaseName?.trim() ?? '');
    if (saved.isNotEmpty) return saved;

    final desc = item.fullDesc.trim();
    if (desc.isNotEmpty) {
      return FileNameFormatter.sanitize(FileNameFormatter.buildBaseName(desc));
    }

    final title = item.title?.trim() ?? '';
    if (title.isNotEmpty) {
      return FileNameFormatter.sanitize(FileNameFormatter.buildBaseName(title));
    }

    return '';
  }

  /// 单作品默认显示路径转 MediaStore 相对路径
  static String relativeSinglePath(String displayPath) {
    var path = displayPath.trim();
    if (path.isEmpty) path = '/';
    while (path.startsWith('/')) {
      path = path.substring(1);
    }
    if (!path.endsWith('/')) path = '$path/';
    return path;
  }
}
