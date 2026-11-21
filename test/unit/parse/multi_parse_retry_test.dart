import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/single_work/media_download_item.dart';
import 'package:yuyin/models/single_work/single_work_result.dart';
import 'package:yuyin/services/multi_work/i_multi_work_extractor.dart';
import 'package:yuyin/services/multi_work/multi_work_extractor.dart';
import 'package:yuyin/services/sniffer/lifecycle/sniff_cancelled_exception.dart';

/// 按调用次数返回预置结果的代理
class _ScriptedDelegate implements IMultiWorkSnifferDelegate {
  _ScriptedDelegate(this.handler);

  final Future<SingleWorkResult> Function(String url, int attempt) handler;
  final Map<String, int> calls = {};

  @override
  Future<SingleWorkResult> sniffVideoUrl(String workUrl) {
    final attempt = (calls[workUrl] ?? 0) + 1;
    calls[workUrl] = attempt;
    return handler(workUrl, attempt);
  }

  @override
  void cancelActiveTask() {}
}

SingleWorkResult _result({String? awemeId, bool empty = false}) {
  return SingleWorkResult(
    items: empty
        ? const []
        : const [
            MediaItem(
              url: 'https://cdn.example.com/video.mp4',
              type: MediaType.video,
              resolution: '1080x1920',
              bitRate: 5000000,
            ),
          ],
    cookie: '',
    isImagePost: false,
    title: '标题',
    awemeId: awemeId,
  );
}

const _target = 'https://www.douyin.com/video/7300000000000000001';

void main() {
  test('空结果自动重试一次后成功', () async {
    final logs = <String>[];
    final delegate = _ScriptedDelegate((url, attempt) async {
      return _result(awemeId: '7300000000000000001', empty: attempt == 1);
    });

    final result = await MultiWorkExtractor(delegate).extractWorks(
      [_target],
      onLog: logs.add,
    );

    expect(result.works.length, 1);
    expect(result.failedUrls, isEmpty);
    expect(delegate.calls[_target], 2);
    expect(logs.any((line) => line.contains('正在重试一次')), isTrue);
  });

  test('两次都失败时进入 failedUrls', () async {
    final delegate = _ScriptedDelegate(
      (url, attempt) async => _result(empty: true),
    );

    final result = await MultiWorkExtractor(delegate).extractWorks([_target]);

    expect(result.works, isEmpty);
    expect(result.failedUrls, [_target]);
    expect(result.failedCount, 1);
    expect(delegate.calls[_target], 2);
  });

  test('结果 id 与显式链接不一致时判失败，不参与去重', () async {
    final delegate = _ScriptedDelegate(
      (url, attempt) async => _result(awemeId: '7300000000000000002'),
    );

    final result = await MultiWorkExtractor(delegate).extractWorks([_target]);

    expect(result.works, isEmpty);
    expect(result.failedUrls, [_target]);
  });

  test('第一次 id 不一致、第二次一致则成功', () async {
    final delegate = _ScriptedDelegate((url, attempt) async {
      return _result(
        awemeId: attempt == 1
            ? '7300000000000000002'
            : '7300000000000000001',
      );
    });

    final result = await MultiWorkExtractor(delegate).extractWorks([_target]);

    expect(result.works.length, 1);
    expect(result.works.single.url, _target);
  });

  test('取消直接上抛且不重试', () async {
    final delegate = _ScriptedDelegate(
      (url, attempt) async => throw const SniffCancelledException(),
    );

    await expectLater(
      MultiWorkExtractor(delegate).extractWorks([_target]),
      throwsA(isA<SniffCancelledException>()),
    );
    expect(delegate.calls[_target], 1);
  });

  test('同一作品的口令与网址仍按结果 id 去重', () async {
    const short = 'https://v.douyin.com/sameWork/';
    final delegate = _ScriptedDelegate((url, attempt) async {
      return _result(awemeId: '7300000000000000009');
    });

    final result = await MultiWorkExtractor(delegate).extractWorks([
      short,
      'https://www.douyin.com/video/7300000000000000009',
    ]);

    expect(result.works.length, 1);
    expect(
      result.works.single.url,
      'https://www.douyin.com/video/7300000000000000009',
    );
  });
}