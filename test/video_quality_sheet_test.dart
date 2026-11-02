import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/widgets/video_quality_sheet.dart';

void main() {
  setUp(() {
    DownloadSettingsStore.resetForTesting(defaultValue: true);
  });

  const testQualities = [
    MediaItem(
      url: 'https://example.com/1080_high.mp4',
      type: MediaType.video,
      resolution: '1080x1920',
      bitRate: 5000000,
      dataSize: 25000000,
    ),
    MediaItem(
      url: 'https://example.com/1080_low.mp4',
      type: MediaType.video,
      resolution: '1080x1920',
      bitRate: 2000000,
      dataSize: 10000000,
    ),
    MediaItem(
      url: 'https://example.com/720.mp4',
      type: MediaType.video,
      resolution: '720x1280',
      bitRate: 1500000,
      dataSize: 8000000,
    ),
  ];

  testWidgets('VideoQualitySheet 在仅显示最高画质开启时只显示各分辨率最优档位', (tester) async {
    DownloadSettingsStore.resetForTesting(defaultValue: true);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => VideoQualitySheet.show(context, testQualities),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // 预期过滤后只有 2 个档位 (1080P 最优 + 720P 最优)
    expect(find.text('选择下载画质（共 2 个档位）'), findsOneWidget);
    expect(find.text('1080x1920'), findsOneWidget);
    expect(find.text('720x1280'), findsOneWidget);
    expect(find.text('最高画质'), findsOneWidget);
  });

  testWidgets('VideoQualitySheet 在仅显示最高画质关闭时展示全部档位', (tester) async {
    DownloadSettingsStore.resetForTesting(defaultValue: false);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => VideoQualitySheet.show(context, testQualities),
              child: const Text('Open Sheet'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open Sheet'));
    await tester.pumpAndSettle();

    // 预期显示全部 3 个档位
    expect(find.text('选择下载画质（共 3 个档位）'), findsOneWidget);
    expect(find.text('1080x1920'), findsNWidgets(2));
    expect(find.text('720x1280'), findsOneWidget);
  });
}

