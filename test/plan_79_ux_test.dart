import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/batch_work/i_work_batch_saver.dart';
import 'package:yuyin/services/user_home/user_home_batch_saver.dart';
import 'package:yuyin/utils/network_detector.dart';
import 'package:yuyin/utils/url/batch_input_parser.dart';
import 'package:yuyin/utils/url/url_classifier.dart';

class _FakeWorkSaver implements IWorkBatchSaver {
  @override
  Future<List<WorkSaveResult>> saveWorks(
    List<SelectedWork> works, {
    MediaSaveTargetResolver? targetResolver,
    CancelToken? cancelToken,
    void Function(int current, int total, String message)? onProgress,
    void Function(String message)? onLog,
  }) async {
    final results = <WorkSaveResult>[];
    for (var i = 0; i < works.length; i++) {
      onProgress?.call(i + 1, works.length, '正在保存 ${i + 1}/${works.length}');
      results.add(
        WorkSaveResult(
          url: works[i].work.url,
          success: true,
          savedTypes: const {MediaType.image},
          savedBaseName: 'base',
        ),
      );
    }
    return results;
  }
}

SelectedWork _imageWork(String url) {
  const parsed = SingleWorkResult(
    items: [MediaItem(url: 'img', type: MediaType.image)],
    cookie: '',
    isImagePost: true,
  );
  return SelectedWork(
    work: SaveWorkItem(url: url, kind: WorkMediaKind.image),
    parsed: parsed,
    items: parsed.items,
  );
}

void main() {
  group('抖音链接识别', () {
    test('iesdouyin 分享链接属于抖音域名', () {
      expect(
        DouyinUrlClassifier.isDouyinLink(
          'https://v.iesdouyin.com/share/video/7600000000000000000/',
        ),
        isTrue,
      );
    });

    test('主页作品浮层链接按 modal_id 归为作品', () {
      const url =
          'https://www.douyin.com/user/MS4wLjABAAAAxyz?modal_id=7600000000000000000';
      final classified = DouyinBatchInputParser.classifyExtractedLink(
        url: url,
        prefix: '',
        suffixLine: '',
      );

      expect(classified.kind, DouyinLinkKind.work);
      expect(
        DouyinBatchInputParser.dedupeKeyForUrl(url),
        'work:7600000000000000000',
      );
    });

    test('普通主页链接仍归为作者主页', () {
      const url = 'https://www.douyin.com/user/MS4wLjABAAAAxyz';
      final classified = DouyinBatchInputParser.classifyExtractedLink(
        url: url,
        prefix: '',
        suffixLine: '',
      );

      expect(classified.kind, DouyinLinkKind.userHome);
      expect(
        DouyinBatchInputParser.dedupeKeyForUrl(url),
        'home:MS4wLjABAAAAxyz',
      );
    });
  });

  group('主页批量保存进度', () {
    test('单作者多作品时进度从作品粒度推进，不会开局 100%', () async {
      final saver = UserHomeBatchSaver(workSaver: _FakeWorkSaver());
      final progress = <({int current, int total})>[];

      await saver.saveAuthors(
        authors: const [UserHomeProfile(secUid: 'sec', nickname: '作者')],
        worksBySecUid: {
          'sec': [for (var i = 0; i < 5; i++) _imageWork('w$i')],
        },
        qualityMode: BatchVideoQualityMode.highest,
        onProgress: (current, total, message) =>
            progress.add((current: current, total: total)),
      );

      expect(progress, isNotEmpty);
      expect(progress.first.total, 5);
      expect(progress.first.current, lessThan(progress.first.total));
      expect(progress.last.current, 5);
    });
  });

  group('网络地址可用性', () {
    test('排除回环与 link-local 地址', () {
      expect(
        NetworkDetector.isUsableAddress(InternetAddress('127.0.0.1')),
        isFalse,
      );
      expect(
        NetworkDetector.isUsableAddress(InternetAddress('169.254.10.20')),
        isFalse,
      );
      expect(
        NetworkDetector.isUsableAddress(InternetAddress('::1')),
        isFalse,
      );
      expect(
        NetworkDetector.isUsableAddress(InternetAddress('fe80::1')),
        isFalse,
      );
      expect(
        NetworkDetector.isUsableAddress(InternetAddress('223.5.5.5')),
        isTrue,
      );
    });
  });
}