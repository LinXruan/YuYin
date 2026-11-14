import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/download_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    DownloadSettingsStore.resetForTesting(defaultValue: true);
  });

  group('DownloadSettingsStore 状态与通知测试', () {
    test('初始状态默认仅显示同分辨率下最高画质 (true)', () {
      expect(DownloadSettingsStore.onlyHighestQualityPerResolution, isTrue);
      expect(DownloadSettingsStore.onlyHighestQualityNotifier.value, isTrue);
    });

    test('切换开关能够同步修改状态与触发 ValueNotifier 通知', () async {
      bool? notifiedValue;
      DownloadSettingsStore.onlyHighestQualityNotifier.addListener(() {
        notifiedValue =
            DownloadSettingsStore.onlyHighestQualityNotifier.value;
      });

      await DownloadSettingsStore.setOnlyHighestQualityPerResolution(false);
      expect(DownloadSettingsStore.onlyHighestQualityPerResolution, isFalse);
      expect(notifiedValue, isFalse);

      await DownloadSettingsStore.setOnlyHighestQualityPerResolution(true);
      expect(DownloadSettingsStore.onlyHighestQualityPerResolution, isTrue);
      expect(notifiedValue, isTrue);
    });
  });

  group('filterHighestQualityPerResolution 画质去重算法测试', () {
    test('空列表与单项列表直接安全返回', () {
      expect(
        DownloadSettingsStore.filterHighestQualityPerResolution([]),
        isEmpty,
      );

      const single = MediaItem(
        url: 'https://example.com/v1.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 4000000,
        dataSize: 20000000,
      );
      final res =
          DownloadSettingsStore.filterHighestQualityPerResolution([single]);
      expect(res.length, 1);
      expect(res.first.url, single.url);
    });

    test('同一分辨率下保留最高码率并额外保留最低档', () {
      const v1080Low = MediaItem(
        url: 'https://example.com/1080_low.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 2000000,
        dataSize: 10000000,
      );
      const v1080High = MediaItem(
        url: 'https://example.com/1080_high.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 5000000,
        dataSize: 25000000,
      );

      // 输入无论何种顺序，均应选出 1080_high
      final res1 = DownloadSettingsStore.filterHighestQualityPerResolution([
        v1080Low,
        v1080High,
      ]);
      expect(res1.length, 2);
      expect(res1.first.url, v1080High.url);
      expect(res1.last.url, v1080Low.url);

      final res2 = DownloadSettingsStore.filterHighestQualityPerResolution([
        v1080High,
        v1080Low,
      ]);
      expect(res2.length, 2);
      expect(res2.first.url, v1080High.url);
      expect(res2.last.url, v1080Low.url);
    });

    test('同一分辨率且码率相同时，保留文件体积更大的项', () {
      const v1 = MediaItem(
        url: 'https://example.com/v1.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 3000000,
        dataSize: 15000000,
      );
      const v2 = MediaItem(
        url: 'https://example.com/v2.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 3000000,
        dataSize: 20000000,
      );

      final res = DownloadSettingsStore.filterHighestQualityPerResolution([
        v1,
        v2,
      ]);
      expect(res.length, 2);
      expect(res.first.url, v2.url);
      expect(res.last.url, v1.url);
    });

    test('横竖屏分辨率归一化：1920x1080 与 1080x1920 视为同一分辨率', () {
      const portrait = MediaItem(
        url: 'https://example.com/portrait.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 4000000,
      );
      const landscape = MediaItem(
        url: 'https://example.com/landscape.mp4',
        type: MediaType.video,
        resolution: '1920x1080',
        bitRate: 2000000,
      );

      final res = DownloadSettingsStore.filterHighestQualityPerResolution([
        landscape,
        portrait,
      ]);
      expect(res.length, 2);
      expect(res.first.url, portrait.url);
      expect(res.last.url, landscape.url);
    });

    test('多分辨率混合时，各分辨率各自保留最优档位，且总体由高到低排序', () {
      const items = [
        MediaItem(
          url: 'https://example.com/1080_low.mp4',
          type: MediaType.video,
          resolution: '1080x1920',
          bitRate: 2000000,
        ),
        MediaItem(
          url: 'https://example.com/720_high.mp4',
          type: MediaType.video,
          resolution: '720x1280',
          bitRate: 1800000,
        ),
        MediaItem(
          url: 'https://example.com/1080_high.mp4',
          type: MediaType.video,
          resolution: '1080x1920',
          bitRate: 5000000,
        ),
        MediaItem(
          url: 'https://example.com/720_low.mp4',
          type: MediaType.video,
          resolution: '720x1280',
          bitRate: 1000000,
        ),
        MediaItem(
          url: 'https://example.com/540.mp4',
          type: MediaType.video,
          resolution: '540x960',
          bitRate: 800000,
        ),
      ];

      final res =
          DownloadSettingsStore.filterHighestQualityPerResolution(items);
      expect(res.length, 3);
      expect(res[0].url, 'https://example.com/1080_high.mp4');
      expect(res[1].url, 'https://example.com/720_high.mp4');
      expect(res[2].url, 'https://example.com/540.mp4');
    });

    test('resolution 缺失时使用 gearName 归一化', () {
      const item1 = MediaItem(
        url: 'https://example.com/g1.mp4',
        type: MediaType.video,
        gearName: '1080p',
        bitRate: 3000000,
      );
      const item2 = MediaItem(
        url: 'https://example.com/g2.mp4',
        type: MediaType.video,
        gearName: '1080p',
        bitRate: 1500000,
      );

      final res = DownloadSettingsStore.filterHighestQualityPerResolution([
        item2,
        item1,
      ]);
      expect(res.length, 2);
      expect(res.first.url, item1.url);
      expect(res.last.url, item2.url);
    });
  });

  group('filterQualities 全局开关控制测试', () {
    const items = [
      MediaItem(
        url: 'https://example.com/1.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 5000000,
      ),
      MediaItem(
        url: 'https://example.com/2.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        bitRate: 2000000,
      ),
    ];

    test('开关开启 (true) 时保留最优与最低档 (2 项)', () {
      DownloadSettingsStore.resetForTesting(defaultValue: true);
      final res = DownloadSettingsStore.filterQualities(items);
      expect(res.length, 2);
      expect(res.first.url, 'https://example.com/1.mp4');
      expect(res.last.url, 'https://example.com/2.mp4');
    });

    test('开关关闭 (false) 时返回全部画质选项 (2 项)', () {
      DownloadSettingsStore.resetForTesting(defaultValue: false);
      final res = DownloadSettingsStore.filterQualities(items);
      expect(res.length, 2);
    });
  });
}

