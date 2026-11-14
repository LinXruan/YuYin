import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../../models/media_item.dart';

/// 原生存储桥接服务：负责调用系统 SAF 目录选择器、保存文件、查询定位与打开
class MediaSaver {
  MediaSaver._();

  static const MethodChannel _storageChannel =
      MethodChannel('com.debug.yuyin/storage');

  /// 唤起 Android 原生 SAF 目录选择器（单作品兼容入口）
  static Future<Map<String, String>?> pickDirectory(MediaType type) {
    return pickDirectoryByName(type.name);
  }

  /// 按目标名称唤起源生 SAF 目录选择器（主页三项复用）
  static Future<Map<String, String>?> pickDirectoryByName(
    String targetName,
  ) async {
    try {
      final result = await _storageChannel.invokeMapMethod<String, dynamic>(
        'pickDirectory',
        {'type': targetName},
      );
      if (result == null) return null;
      return {
        'uri': result['uri']?.toString() ?? '',
        'displayPath': result['displayPath']?.toString() ?? '',
      };
    } on PlatformException catch (e) {
      debugPrint('[MediaSaver] pickDirectory 异常: ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[MediaSaver] pickDirectory 未知异常: $e');
      return null;
    }
  }

  /// 保存文件到本地（默认 MediaStore 目录或用户自定义的 SAF 目录）
  static Future<bool> saveMedia({
    required String tempFilePath,
    required MediaType type,
    String? treeUri,
    required String fileName,
    String? relativePath,
    List<String> subDirNames = const [],
    String collection = 'auto',
  }) async {
    try {
      final success = await _storageChannel.invokeMethod<bool>(
        'saveMedia',
        {
          'filePath': tempFilePath,
          'mediaType': type.name,
          'treeUri': treeUri,
          'fileName': fileName,
          'relativePath': relativePath,
          'subDirNames': subDirNames,
          'collection': collection,
        },
      );
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MediaSaver] saveMedia 异常: ${e.message}');
      throw Exception('保存文件失败: ${e.message ?? e.code}');
    } catch (e) {
      debugPrint('[MediaSaver] saveMedia 未知异常: $e');
      throw Exception('保存文件失败: $e');
    }
  }

  /// 批量查询当前保存位置中是否存在对应资源
  static Future<List<SavedMediaAvailability>> querySavedMedia(
    List<SavedMediaQuery> queries,
  ) async {
    if (queries.isEmpty) return const [];
    try {
      final raw = await _storageChannel.invokeListMethod<dynamic>(
        'querySavedMedia',
        {'queries': queries.map((query) => query.toMap()).toList()},
      );
      if (raw == null) return const [];
      return raw
          .whereType<Map>()
          .map((item) =>
              SavedMediaAvailability.fromMap(Map<String, dynamic>.from(item)))
          .toList();
    } on PlatformException catch (e) {
      debugPrint('[MediaSaver] querySavedMedia 异常: ${e.message}');
      return const [];
    } catch (e) {
      debugPrint('[MediaSaver] querySavedMedia 未知异常: $e');
      return const [];
    }
  }

  /// 优先跳转文件管理器文件夹，失败时打开文件
  static Future<bool> openMediaLocation({
    required String? contentUri,
    required String? folderUri,
    required String mimeType,
  }) async {
    try {
      final success = await _storageChannel.invokeMethod<bool>(
        'openMediaLocation',
        {
          'contentUri': contentUri,
          'folderUri': folderUri,
          'mimeType': mimeType,
        },
      );
      return success ?? false;
    } on PlatformException catch (e) {
      debugPrint('[MediaSaver] openMediaLocation 异常: ${e.message}');
      return false;
    } catch (e) {
      debugPrint('[MediaSaver] openMediaLocation 未知异常: $e');
      return false;
    }
  }
}
