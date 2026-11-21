import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/save_page/save_work_item.dart';
import 'package:yuyin/models/save_page/selection/terminal_seed.dart';
import 'package:yuyin/models/save_page/work_kind.dart';
import 'package:yuyin/models/single_work/media_download_item.dart';
import 'package:yuyin/models/single_work/single_work_result.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/services/selection/session_work_preparer.dart';

const String _videoUrl = 'https://www.douyin.com/video/7000000000000000001';
const String _imageUrl = 'https://www.douyin.com/note/7000000000000000002';

SaveSelectionSession _session() => SaveSelectionSession.multiWork(
      works: const [
        SaveWorkItem(url: _videoUrl, kind: WorkMediaKind.video),
        SaveWorkItem(url: _imageUrl, kind: WorkMediaKind.image),
      ],
      seed: const TerminalSeed(),
    );

Future<SingleWorkResult> _parsed(String url) async => SingleWorkResult(
      items: const [
        MediaItem(url: 'https://cdn.example.com/1.mp4', type: MediaType.video),
      ],
      cookie: '',
      isImagePost: false,
      title: url,
    );

void main() {
  group('SessionWorkPreparer 取消', () {
    test('开始前已取消则不解析任何作品', () async {
      var calls = 0;
      final session = _session();
      final result = await SessionWorkPreparer.prepare(
        session,
        [_videoUrl, _imageUrl],
        (url) {
          calls++;
          return _parsed(url);
        },
        isCancelled: () => true,
      );

      expect(result, isEmpty);
      expect(calls, 0);
      session.close();
    });

    test('首条完成后取消，只保留已完成作品', () async {
      var calls = 0;
      final session = _session();
      final result = await SessionWorkPreparer.prepare(
        session,
        [_videoUrl, _imageUrl],
        (url) {
          calls++;
          return _parsed(url);
        },
        isCancelled: () => calls >= 1,
      );

      expect(calls, 1);
      expect(result.length, 1);
      session.close();
    });

    test('取消检查发生在每条前后，进度只覆盖已选作品', () async {
      final session = _session();
      final progress = <String>[];
      await SessionWorkPreparer.prepare(
        session,
        [_videoUrl, _imageUrl],
        _parsed,
        onProgress: (current, total, label) {
          progress.add('$current/$total $label');
        },
      );

      expect(progress.length, 2);
      expect(progress.first, startsWith('1/2 '));
      expect(progress.last, startsWith('2/2 '));
      session.close();
    });
  });
}
