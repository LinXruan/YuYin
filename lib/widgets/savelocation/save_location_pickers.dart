import 'package:flutter/material.dart';

import '../../models/media_item.dart';
import '../../services/media/media_saver.dart';
import '../../utils/savelocation/save_location_store.dart';

/// 保存位置选择器：打开系统目录选择并写回 Store。
class SaveLocationPickers {
  SaveLocationPickers._();

  static Future<void> pickDirectory(
    BuildContext context,
    SaveLocationTarget target,
  ) async {
    final result = await MediaSaver.pickDirectoryByName(target.name);
    if (result == null || result['displayPath']?.isNotEmpty != true) return;

    if (target.isHome) {
      await SaveLocationStore.updateHomeLocation(
        target.mediaType,
        uri: result['uri'],
        displayPath: result['displayPath']!,
      );
    } else {
      await SaveLocationStore.updateLocation(
        target.mediaType,
        uri: result['uri'],
        displayPath: result['displayPath']!,
      );
    }
  }

  static IconData iconFor(SaveLocationTarget target) {
    final base = switch (target.mediaType) {
      MediaType.video => Icons.movie_outlined,
      MediaType.image => Icons.image_outlined,
      MediaType.audio => Icons.music_note_outlined,
    };
    return target.isHome ? Icons.folder_special_outlined : base;
  }
}
