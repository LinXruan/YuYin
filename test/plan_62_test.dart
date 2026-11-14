import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/batch_work/i_work_batch_saver.dart';
import 'package:yuyin/services/batch_work/work_batch_saver.dart';
import 'package:yuyin/services/user_home/user_home_batch_saver.dart';
import 'package:yuyin/services/video_downloader.dart';

class _FakeDownloader implements IWorkDownloadDelegate {
  _FakeDownloader();

  final List<List<MediaItem>> calls = [];
  bool failNext = false;

  @override
  Future<Set<MediaType>> downloadItems(
    List<MediaItem> items, {
    String? cookie,
    String? baseTitle,
    CancelToken? cancelToken,
    MediaSaveTargetResolver? targetResolver,
    required void Function(int current, int total, double itemProgress) onProgress,
  }) async {
    if (failNext) throw StateError('disk full');
    calls.add(List<MediaItem>.from(items));
    onProgress(1, items.length, 1.0);
    return items.map((item) => item.type).toSet();
  }
}

SaveWorkItem _work(String url, WorkMediaKind kind) =>
    SaveWorkItem(url: url, kind: kind, title: '作品');

SingleWorkResult _parsed(List<MediaItem> items) => SingleWorkResult(
  items: items,
  cookie: 'c=1',
  isImagePost: true,
);

SelectedWork _selected(SaveWorkItem work, List<MediaItem> items) => SelectedWork(
  work: work,
  parsed: _parsed(items),
  items: items,
);

void main() {
  group('WorkBatchSaver 按矩阵解算结果落盘', () {
    test('每个作品只保存传入的资源', () async {
      final downloader = _FakeDownloader();
      final saver = WorkBatchSaver(downloader: downloader);
      final image = MediaItem(url: 'img1', type: MediaType.image);
      final audio = MediaItem(url: 'a1', type: MediaType.audio);

      final results = await saver.saveWorks([
        _selected(_work('w1', WorkMediaKind.image), [image, audio]),
      ]);

      expect(results.single.success, isTrue);
      expect(results.single.savedTypes, {MediaType.image, MediaType.audio});
      expect(downloader.calls.single.map((item) => item.url), ['img1', 'a1']);
    });

    test('空资源不落盘并返回失败', () async {
      final downloader = _FakeDownloader();
      final saver = WorkBatchSaver(downloader: downloader);

      final results = await saver.saveWorks([
        _selected(_work('w1', WorkMediaKind.image), const []),
      ]);

      expect(results.single.success, isFalse);
      expect(downloader.calls, isEmpty);
    });

    test('下载异常转为失败结果，不中断整批', () async {
      final downloader = _FakeDownloader()..failNext = true;
      final saver = WorkBatchSaver(downloader: downloader);
      final image = MediaItem(url: 'img1', type: MediaType.image);

      final results = await saver.saveWorks([
        _selected(_work('w1', WorkMediaKind.image), [image]),
      ]);

      expect(results.single.success, isFalse);
      expect(results.single.error, contains('disk full'));
    });

    test('取消后立即抛出取消异常', () async {
      final downloader = _FakeDownloader();
      final saver = WorkBatchSaver(downloader: downloader);
      final token = CancelToken()..cancel('stop');
      final image = MediaItem(url: 'img1', type: MediaType.image);

      expect(
        () => saver.saveWorks(
          [_selected(_work('w1', WorkMediaKind.image), [image])],
          cancelToken: token,
        ),
        throwsA(isA<DouyinDownloadCancelledException>()),
      );
    });
  });

  group('UserHomeBatchSaver 按作者写入目录', () {
    test('按作者聚合成功数量并跳过空作者', () async {
      final downloader = _FakeDownloader();
      final workSaver = WorkBatchSaver(downloader: downloader);
      final saver = UserHomeBatchSaver(workSaver: workSaver);

      final authors = [
        const UserHomeProfile(secUid: 'a1', nickname: '作者一'),
        const UserHomeProfile(secUid: 'a2', nickname: '作者二'),
      ];
      final works = {
        'a1': [
          _selected(
            _work('w1', WorkMediaKind.image),
            [MediaItem(url: 'img1', type: MediaType.image)],
          ),
        ],
      };

      final result = await saver.saveAuthors(
        authors: authors,
        worksBySecUid: works,
        qualityMode: BatchVideoQualityMode.highest,
      );

      expect(result.authors.length, 1);
      expect(result.authors.single.success, isTrue);
      expect(result.totalSaved, 1);
    });
  });
}