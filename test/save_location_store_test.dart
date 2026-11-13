import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/save_location_store.dart';

void main() {
  group('SaveLocationConfig 实体与序列化测试', () {
    test('初始默认值与分类路径符合规范', () {
      const config = SaveLocationConfig();
      expect(config.videoDisplayPath, equals('/Movies/YuYin/'));
      expect(config.imageDisplayPath, equals('/Pictures/YuYin/'));
      expect(config.audioDisplayPath, equals('/Music/YuYin/'));
      expect(config.videoUri, isNull);
      expect(config.imageUri, isNull);
      expect(config.audioUri, isNull);
      expect(config.isAllDefault, isTrue);

      expect(config.getDisplayPath(MediaType.video), equals('/Movies/YuYin/'));
      expect(config.getDisplayPath(MediaType.image), equals('/Pictures/YuYin/'));
      expect(config.getDisplayPath(MediaType.audio), equals('/Music/YuYin/'));

      expect(config.homeVideoDisplayPath, equals('/Download/YuYin/'));
      expect(config.homeImageDisplayPath, equals('/Download/YuYin/'));
      expect(config.homeAudioDisplayPath, equals('/Download/YuYin/'));
      expect(config.homeVideoUri, isNull);
      expect(config.homeImageUri, isNull);
      expect(config.homeAudioUri, isNull);
      expect(config.getHomeDisplayPath(MediaType.video), equals('/Download/YuYin/'));
      expect(config.getHomeTreeUri(MediaType.audio), isNull);
    });

    test('copyWith 更新属性与 isAllDefault 判定', () {
      const config = SaveLocationConfig();
      final updated = config.copyWith(
        imageUri: () => 'content://tree/primary:Pictures/Custom',
        imageDisplayPath: '/Pictures/Custom/',
      );

      expect(updated.imageUri, equals('content://tree/primary:Pictures/Custom'));
      expect(updated.imageDisplayPath, equals('/Pictures/Custom/'));
      expect(updated.videoDisplayPath, equals('/Movies/YuYin/'));
      expect(updated.isAllDefault, isFalse);

      final homeUpdated = config.copyWith(
        homeImageUri: () => 'content://tree/primary:Download/YuYin/Home',
        homeImageDisplayPath: '/Download/YuYin/Home/',
      );
      expect(homeUpdated.homeImageUri, isNotNull);
      expect(homeUpdated.homeImageDisplayPath, equals('/Download/YuYin/Home/'));
      expect(homeUpdated.homeVideoDisplayPath, equals('/Download/YuYin/'));
      expect(homeUpdated.isAllDefault, isFalse);
    });

    test('toJson 与 fromJson 序列化一致性', () {
      const original = SaveLocationConfig(
        videoUri: 'content://tree/primary:Movies/Douyin',
        videoDisplayPath: '/Movies/Douyin/',
        imageUri: 'content://tree/primary:DCIM/Camera',
        imageDisplayPath: '/DCIM/Camera/',
        audioUri: 'content://tree/primary:Music/Favorites',
        audioDisplayPath: '/Music/Favorites/',
        homeVideoUri: 'content://tree/primary:Download/YuYin/Video',
        homeVideoDisplayPath: '/Download/YuYin/Video/',
        homeImageUri: 'content://tree/primary:Download/YuYin/Image',
        homeImageDisplayPath: '/Download/YuYin/Image/',
        homeAudioUri: 'content://tree/primary:Download/YuYin/Audio',
        homeAudioDisplayPath: '/Download/YuYin/Audio/',
      );

      final json = original.toJson();
      final restored = SaveLocationConfig.fromJson(json);

      expect(restored.videoUri, equals(original.videoUri));
      expect(restored.videoDisplayPath, equals(original.videoDisplayPath));
      expect(restored.imageUri, equals(original.imageUri));
      expect(restored.imageDisplayPath, equals(original.imageDisplayPath));
      expect(restored.audioUri, equals(original.audioUri));
      expect(restored.audioDisplayPath, equals(original.audioDisplayPath));
      expect(restored.homeVideoUri, equals(original.homeVideoUri));
      expect(restored.homeVideoDisplayPath, equals(original.homeVideoDisplayPath));
      expect(restored.homeImageUri, equals(original.homeImageUri));
      expect(restored.homeImageDisplayPath, equals(original.homeImageDisplayPath));
      expect(restored.homeAudioUri, equals(original.homeAudioUri));
      expect(restored.homeAudioDisplayPath, equals(original.homeAudioDisplayPath));
      expect(restored.isAllDefault, isFalse);
    });
  });

  group('SaveLocationStore 状态通知测试', () {
    setUp(() {
      SaveLocationStore.notifier.value = const SaveLocationConfig();
    });

    test('updateLocation 触发全局通知源更新', () {
      expect(SaveLocationStore.isAllDefault, isTrue);

      SaveLocationStore.notifier.value =
          SaveLocationStore.notifier.value.copyWith(
        videoUri: () => 'content://tree/test',
        videoDisplayPath: '/自定义视频/',
      );

      expect(
        SaveLocationStore.getDisplayPath(MediaType.video),
        equals('/自定义视频/'),
      );
      expect(SaveLocationStore.getTreeUri(MediaType.video), equals('content://tree/test'));
      expect(SaveLocationStore.isAllDefault, isFalse);

      SaveLocationStore.notifier.value =
          SaveLocationStore.notifier.value.copyWith(
        homeAudioUri: () => 'content://tree/home_audio',
        homeAudioDisplayPath: '/Download/HomeAudio/',
      );
      expect(
        SaveLocationStore.getHomeDisplayPath(MediaType.audio),
        equals('/Download/HomeAudio/'),
      );
      expect(
        SaveLocationStore.getHomeTreeUri(MediaType.audio),
        equals('content://tree/home_audio'),
      );
    });

    test('MediaTypeX 扩展方法返回正确属性', () {
      expect(MediaType.video.label, equals('视频'));
      expect(MediaType.image.label, equals('图片'));
      expect(MediaType.audio.label, equals('音频'));

      expect(MediaType.video.defaultDisplayPath, equals('/Movies/YuYin/'));
      expect(MediaType.image.defaultDisplayPath, equals('/Pictures/YuYin/'));
      expect(MediaType.audio.defaultDisplayPath, equals('/Music/YuYin/'));
    });
  });
}

