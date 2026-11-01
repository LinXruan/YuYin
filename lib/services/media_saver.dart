import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/media_item.dart';

/// 原生存储桥接服务：负责调用系统 SAF 目录选择器以及分类保存文件
class MediaSaver {
  MediaSaver._();

  static const MethodChannel _storageChannel =
      MethodChannel('com.debug.yuyin/storage');

  /// 唤起 Android 原生 SAF 目录选择器
  ///
  /// 返回包含 `uri` 与 `displayPath` 的 Map；若用户取消选择返回 null
  static Future<Map<String, String>?> pickDirectory(MediaType type) async {
    try {
      final result = await _storageChannel.invokeMapMethod<String, dynamic>(
        'pickDirectory',
        {'type': type.name},
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
  }) async {
    try {
      final success = await _storageChannel.invokeMethod<bool>(
        'saveMedia',
        {
          'filePath': tempFilePath,
          'mediaType': type.name,
          'treeUri': treeUri,
          'fileName': fileName,
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
}

