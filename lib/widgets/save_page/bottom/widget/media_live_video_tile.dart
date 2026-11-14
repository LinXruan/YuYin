import 'package:flutter/material.dart';

import '../../../../models/media_item.dart';

/// 实况视频占位图
class MediaLiveVideoTile extends StatelessWidget {
  const MediaLiveVideoTile({super.key, required this.item});

  final MediaItem item;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.motion_photos_on, color: Colors.white, size: 30),
          const SizedBox(height: 6),
          const Text(
            '实况视频 (LIVE)',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 12),
          ),
          if (item.resolution?.isNotEmpty == true)
            Text(
              item.resolution!,
              style: const TextStyle(color: Colors.white70, fontSize: 11),
            ),
        ],
      ),
    );
  }
}
