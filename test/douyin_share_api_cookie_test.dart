import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/share/client/douyin_share_api.dart';

import 'share_api_fixtures.dart';

void main() {
  group('DouyinShareApi.pickImageUrl', () {
    test('优先 jpeg/jpg，否则取最后一项', () {
      expect(
        DouyinShareApi.pickImageUrl({
          'url_list': ['https://a.webp', 'https://a.jpeg'],
        }),
        'https://a.jpeg',
      );
      expect(
        DouyinShareApi.pickImageUrl({
          'url_list': ['https://a.webp', 'https://b.webp'],
        }),
        'https://b.webp',
      );
    });
  });

  group('DouyinShareApi Cookie 重试', () {
    test('首次无 Cookie 拿到 ttwid 后重试成功', () async {
      final adapter = FakeAdapter([
        fakeResponse('<html>verify</html>', setCookies: ['ttwid=abc; Path=/']),
        fakeResponse(htmlFor(imagePostRoot())),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final api = DouyinShareApi(dio: dio);

      final result = await api.fetchShareItem('123');

      expect(result, isNotNull);
      expect(result.items, isNotEmpty);
      expect(adapter.requests, hasLength(2));
      expect(headerValue(adapter.requests[0], 'Cookie'), isNull);
      expect(headerValue(adapter.requests[1], 'Cookie'), 'ttwid=abc');
    });

    test('缓存 Cookie 跨调用复用', () async {
      final adapter = FakeAdapter([
        fakeResponse('<html>verify</html>', setCookies: ['ttwid=abc; Path=/']),
        fakeResponse(htmlFor(imagePostRoot())),
        fakeResponse(htmlFor(imagePostRoot())),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final api = DouyinShareApi(dio: dio);

      await api.fetchShareItem('123');
      await api.fetchShareItem('123');

      expect(adapter.requests, hasLength(3));
      expect(headerValue(adapter.requests[2], 'Cookie'), 'ttwid=abc');
    });

    test('没有新 Cookie 时不重试', () async {
      final adapter = FakeAdapter([fakeResponse('<html>verify</html>')]);
      final dio = Dio()..httpClientAdapter = adapter;
      final api = DouyinShareApi(dio: dio);

      await expectLater(
        api.fetchShareItem('123'),
        throwsA(isA<DouyinShareException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('4xx 响应也读取 Set-Cookie 并重试', () async {
      final adapter = FakeAdapter([
        fakeResponse(
          '<html>blocked</html>',
          statusCode: 403,
          setCookies: ['ttwid=abc'],
        ),
        fakeResponse(htmlFor(imagePostRoot())),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final api = DouyinShareApi(dio: dio);

      final result = await api.fetchShareItem('123');

      expect(result, isNotNull);
      expect(adapter.requests, hasLength(2));
      expect(headerValue(adapter.requests[1], 'Cookie'), 'ttwid=abc');
    });

    test('超过总预算抛分享页异常', () async {
      final dio = Dio()..httpClientAdapter = HangingAdapter();
      final api = DouyinShareApi(dio: dio);

      await expectLater(
        api.fetchShareItem(
          '123',
          totalTimeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<DouyinShareException>()),
      );
    });

    test('外部取消映射为取消异常', () async {
      final dio = Dio()..httpClientAdapter = CancelableAdapter();
      final api = DouyinShareApi(dio: dio);
      final token = CancelToken();

      final future = api.fetchShareItem('123', cancelToken: token);
      token.cancel('test');

      await expectLater(
        future,
        throwsA(isA<DouyinShareCancelledException>()),
      );
    });

    test('解析 Set-Cookie 与合并 Cookie', () {
      expect(
        DouyinShareApi.parseSetCookies([
          'ttwid=abc; Path=/; HttpOnly',
          'a=b=c; Max-Age=0',
          'bad',
        ]),
        ['ttwid=abc'],
      );
      expect(
        DouyinShareApi.mergeCookieHeader('ttwid=old; x=1', [
          'TTWID=new',
          'y=2',
        ]),
        'TTWID=new; x=1; y=2',
      );
    });

    test('sharePageUrl 与 pickBestVideo 顶层回退', () {
      expect(
        DouyinShareApi.sharePageUrl('123'),
        'https://www.iesdouyin.com/share/video/123/',
      );

      final item = DouyinShareApi.pickBestVideo({
        'play_addr': {
          'url_list': ['https://cdn.example.com/top.mp4'],
          'width': 1080,
          'height': 1920,
          'data_size': 100,
        },
      });
      expect(item, isNotNull);
      expect(item!.url, contains('top.mp4'));
      expect(item.dataSize, 100);
    });
  });
}
