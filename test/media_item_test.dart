import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';

void main() {
  group('MediaItem 模型测试', () {
    test('正确解析 audio 类型 JSON', () {
      final json = {
        'url': 'https://example.com/audio.mp3',
        'mediaType': 'audio',
        'dataSize': 1024 * 1024 * 3,
        'gearName': '标准音质',
      };

      final item = MediaItem.fromJson(json);
      expect(item.type, equals(MediaType.audio));
      expect(item.url, equals('https://example.com/audio.mp3'));
      expect(item.formattedSize, equals('3.0 MB'));
      expect(item.gearName, equals('标准音质'));
    });

    test('正确解析 video 与 image 类型', () {
      final videoItem = MediaItem.fromJson({
        'url': 'https://example.com/video.mp4',
        'mediaType': 'video',
        'resolution': '1080x1920',
      });
      expect(videoItem.type, equals(MediaType.video));
      expect(videoItem.resolutionLabel, equals('1080P'));

      final imageItem = MediaItem.fromJson({
        'url': 'https://example.com/image.jpg',
        'mediaType': 'image',
      });
      expect(imageItem.type, equals(MediaType.image));
    });

    test('SniffResult 统计各类媒体数量', () {
      final result = SniffResult(
        items: [
          const MediaItem(url: 'v1', type: MediaType.video),
          const MediaItem(url: 'i1', type: MediaType.image),
          const MediaItem(url: 'i2', type: MediaType.image),
          const MediaItem(url: 'a1', type: MediaType.audio),
        ],
        cookie: 'test_cookie',
        isImagePost: true,
      );

      expect(result.videoCount, equals(1));
      expect(result.imageCount, equals(2));
      expect(result.audioCount, equals(1));
    });
  });
}

