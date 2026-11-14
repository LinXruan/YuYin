import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/share/client/douyin_share_api.dart';

void main() {
  group('DouyinShareApi.extractRouterDataJson', () {
    test('提取普通 _ROUTER_DATA', () {
      const html =
          '<script>window._ROUTER_DATA = {"loaderData":{"x":1}};</script>';
      expect(
        DouyinShareApi.extractRouterDataJson(html),
        '{"loaderData":{"x":1}}',
      );
    });

    test('字符串内的 } 不会截断 JSON', () {
      const html =
          r'<script>window._ROUTER_DATA = {"a":"}","b":{"c":1}};</script>';
      final json = DouyinShareApi.extractRouterDataJson(html);
      expect(json, isNotNull);
      final decoded = jsonDecode(json!) as Map<String, dynamic>;
      expect(decoded['a'], '}');
      expect((decoded['b'] as Map)['c'], 1);
    });

    test('跳过字符串中的假 marker，取真正的赋值', () {
      const html = '<script>var s = "window._ROUTER_DATA = {}";'
          'window._ROUTER_DATA = {"loaderData":{"x":1}};</script>';
      final json = DouyinShareApi.extractRouterDataJson(html);
      expect(json, contains('"loaderData"'));
    });

    test('缺失或截断返回 null', () {
      expect(DouyinShareApi.extractRouterDataJson('<html></html>'), isNull);
      expect(
        DouyinShareApi.extractRouterDataJson(
          '<script>window._ROUTER_DATA = {"loaderData": {"x":1}</script>',
        ),
        isNull,
      );
    });
  });

  group('DouyinShareApi.parseShareHtml', () {
    test('图片与实况图解析', () {
      final result =
          DouyinShareApi.parseShareHtml(_htmlFor(_imagePostRoot()), '123');
      expect(result, isNotNull);
      expect(result!.isImagePost, isTrue);
      expect(result.items.length, 3);

      expect(result.items[0].type, MediaType.image);
      expect(result.items[0].url, contains('a.jpeg'));
      expect(result.items[1].type, MediaType.image);
      expect(result.items[1].url, contains('b.jpeg'));
      expect(result.items[2].type, MediaType.video);
      expect(result.items[2].url, contains('live.mp4'));
      expect(result.items[2].resolution, '1080x1920');
      expect(result.items[2].dataSize, 12345);
    });

    test('图文作品提取配乐音频 (music 与顶层 video.play_addr)', () {
      final rootWithMusic = {
        'loaderData': {
          'note_(id)/page': {
            'videoInfoRes': {
              'item_list': [
                {
                  'aweme_id': '789',
                  'images': [
                    {
                      'url_list': ['https://p3.douyinpic.com/img1.jpeg'],
                      'width': 1080,
                      'height': 1440,
                    },
                  ],
                  'music': {
                    'title': '测试配乐',
                    'play_url': {
                      'url_list': ['https://sf1-cdn-tos.douyinstatic.com/obj/tos-cn-ve-2774/bgm.m4a'],
                    },
                  },
                },
              ],
            },
          },
        },
      };

      final result1 =
          DouyinShareApi.parseShareHtml(_htmlFor(rootWithMusic), '789');
      expect(result1, isNotNull);
      expect(result1!.isImagePost, isTrue);
      expect(result1.imageCount, 1);
      expect(result1.audioCount, 1);
      expect(result1.items.last.type, MediaType.audio);
      expect(result1.items.last.url, contains('bgm.m4a'));
      expect(result1.items.last.gearName, '配乐');

      final rootWithVideoBgm = {
        'loaderData': {
          'note_(id)/page': {
            'videoInfoRes': {
              'item_list': [
                {
                  'aweme_id': '790',
                  'images': [
                    {
                      'url_list': ['https://p3.douyinpic.com/img2.jpeg'],
                    },
                  ],
                  'video': {
                    'play_addr': {
                      'url_list': ['https://www.iesdouyin.com/aweme/v1/play/?video_id=v0300fg10000ctn'],
                    },
                  },
                },
              ],
            },
          },
        },
      };

      final result2 =
          DouyinShareApi.parseShareHtml(_htmlFor(rootWithVideoBgm), '790');
      expect(result2, isNotNull);
      expect(result2!.isImagePost, isTrue);
      expect(result2.imageCount, 1);
      expect(result2.audioCount, 1);
      expect(result2.items.last.type, MediaType.audio);
      expect(result2.items.last.url, contains('aweme/v1/play'));
    });

    test('视频多档位排序、跳过 dash、按档位名去重', () {
      final result =
          DouyinShareApi.parseShareHtml(_htmlFor(_videoRoot()), '456');
      expect(result, isNotNull);
      expect(result!.isImagePost, isFalse);
      expect(result.items.length, 2);
      expect(result.items[0].resolution, '1080x1920');
      expect(result.items[0].bitRate, 2800000);
      expect(result.items[0].dataSize, 14000000);
      expect(result.items[1].resolution, '720x1280');
      expect(result.items[1].bitRate, 850000);
      expect(result.items.any((item) => item.url.contains('dash')), isFalse);
    });

    test('image_post_info.images 兼容', () {
      final root = {
        'loaderData': {
          'note_(id)/page': {
            'videoInfoRes': {
              'item_list': [
                {
                  'aweme_id': '123',
                  'image_post_info': {
                    'images': [
                      {
                        'url_list': ['https://p3.douyinpic.com/a.jpeg'],
                        'width': 1080,
                        'height': 1440,
                      },
                    ],
                  },
                },
              ],
            },
          },
        },
      };
      final result = DouyinShareApi.parseShareHtml(_htmlFor(root), '123');
      expect(result, isNotNull);
      expect(result!.isImagePost, isTrue);
      expect(result.items.single.url, contains('a.jpeg'));
    });

    test('正确提取作品文案描述（无需独立标题）', () {
      final root = {
        'loaderData': {
          'video_(id)/page': {
            'videoInfoRes': {
              'item_list': [
                {
                  'aweme_id': '789',
                  'desc': '这是作品文案内容',
                  'video': {
                    'play_addr': {
                      'url_list': ['https://cdn.example.com/v.mp4'],
                    },
                  },
                },
              ],
            },
          },
        },
      };
      final result = DouyinShareApi.parseShareHtml(_htmlFor(root), '789');
      expect(result, isNotNull);
      expect(result!.desc, '这是作品文案内容');
    });

    test('视频作品正确捕获封面 coverUrl 并排斥视频地址', () {
      final root = {
        'loaderData': {
          'video_(id)/page': {
            'videoInfoRes': {
              'item_list': [
                {
                  'aweme_id': '888',
                  'desc': '封面测试作品',
                  'video': {
                    'cover': {
                      'url_list': [
                        'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover1.jpeg',
                      ],
                    },
                    'play_addr': {
                      'url_list': ['https://cdn.example.com/video.mp4'],
                    },
                  },
                },
              ],
            },
          },
        },
      };
      final result = DouyinShareApi.parseShareHtml(_htmlFor(root), '888');
      expect(result, isNotNull);
      expect(result!.isImagePost, isFalse);
      expect(result.coverUrl, 'https://p3-pc.douyinpic.com/tos-cn-p-0015/cover1.jpeg');
    });

    test('视频作品优先捕获自定义封面 cover 并排斥视频地址', () {
      final root = {
        'loaderData': {
          'video_(id)/page': {
            'videoInfoRes': {
              'item_list': [
                {
                  'aweme_id': '889',
                  'desc': '封面测试作品',
                  'video': {
                    'cover': {
                      'url_list': [
                        'https://p3-pc.douyinpic.com/tos-cn-p-0015/creator_custom_cover.jpeg',
                      ],
                    },
                    'origin_cover': {
                      'url_list': [
                        'https://p3-pc.douyinpic.com/tos-cn-p-0015/raw_zero_frame_black.jpeg',
                      ],
                    },
                    'play_addr': {
                      'url_list': ['https://cdn.example.com/video.mp4'],
                    },
                  },
                },
              ],
            },
          },
        },
      };
      final result = DouyinShareApi.parseShareHtml(_htmlFor(root), '889');
      expect(result, isNotNull);
      expect(
        result!.coverUrl,
        'https://p3-pc.douyinpic.com/tos-cn-p-0015/creator_custom_cover.jpeg',
      );
    });

    test('目标作品不是第一项时优先匹配 aweme_id', () {
      final root = {
        'loaderData': {
          'video_(id)/page': {
            'videoInfoRes': {
              'item_list': [
                {
                  'aweme_id': '111',
                  'video': {
                    'play_addr': {
                      'url_list': ['https://cdn.example.com/other.mp4'],
                    },
                  },
                },
                {
                  'aweme_id': '456',
                  'video': {
                    'play_addr': {
                      'url_list': ['https://cdn.example.com/target.mp4'],
                    },
                  },
                },
              ],
            },
          },
        },
      };
      final result = DouyinShareApi.parseShareHtml(_htmlFor(root), '456');
      expect(result, isNotNull);
      expect(result!.items.single.url, contains('target.mp4'));
    });

    test('风控页/空 item_list/无媒体返回 null', () {
      expect(
        DouyinShareApi.parseShareHtml(
          _htmlFor({
            'loaderData': {
              'video_(id)/page': {'video_layout': {}},
            },
          }),
          '123',
        ),
        isNull,
      );
      expect(
        DouyinShareApi.parseShareHtml(
          _htmlFor({
            'loaderData': {
              'video_(id)/page': {
                'videoInfoRes': {'item_list': []},
              },
            },
          }),
          '123',
        ),
        isNull,
      );
      expect(
        DouyinShareApi.parseShareHtml(
          _htmlFor({
            'loaderData': {
              'video_(id)/page': {
                'videoInfoRes': {
                  'item_list': [
                    {'aweme_id': '123'},
                  ],
                },
              },
            },
          }),
          '123',
        ),
        isNull,
      );
    });
  });

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
      final adapter = _FakeAdapter([
        _response('<html>verify</html>', setCookies: ['ttwid=abc; Path=/']),
        _response(_htmlFor(_imagePostRoot())),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final api = DouyinShareApi(dio: dio);

      final result = await api.fetchShareItem('123');

      expect(result, isNotNull);
      expect(result.items, isNotEmpty);
      expect(adapter.requests, hasLength(2));
      expect(_headerValue(adapter.requests[0], 'Cookie'), isNull);
      expect(_headerValue(adapter.requests[1], 'Cookie'), 'ttwid=abc');
    });

    test('缓存 Cookie 跨调用复用', () async {
      final adapter = _FakeAdapter([
        _response('<html>verify</html>', setCookies: ['ttwid=abc; Path=/']),
        _response(_htmlFor(_imagePostRoot())),
        _response(_htmlFor(_imagePostRoot())),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final api = DouyinShareApi(dio: dio);

      await api.fetchShareItem('123');
      await api.fetchShareItem('123');

      expect(adapter.requests, hasLength(3));
      expect(_headerValue(adapter.requests[2], 'Cookie'), 'ttwid=abc');
    });

    test('没有新 Cookie 时不重试', () async {
      final adapter = _FakeAdapter([_response('<html>verify</html>')]);
      final dio = Dio()..httpClientAdapter = adapter;
      final api = DouyinShareApi(dio: dio);

      await expectLater(
        api.fetchShareItem('123'),
        throwsA(isA<DouyinShareException>()),
      );
      expect(adapter.requests, hasLength(1));
    });

    test('4xx 响应也读取 Set-Cookie 并重试', () async {
      final adapter = _FakeAdapter([
        _response(
          '<html>blocked</html>',
          statusCode: 403,
          setCookies: ['ttwid=abc'],
        ),
        _response(_htmlFor(_imagePostRoot())),
      ]);
      final dio = Dio()..httpClientAdapter = adapter;
      final api = DouyinShareApi(dio: dio);

      final result = await api.fetchShareItem('123');

      expect(result, isNotNull);
      expect(adapter.requests, hasLength(2));
      expect(_headerValue(adapter.requests[1], 'Cookie'), 'ttwid=abc');
    });

    test('超过总预算抛分享页异常', () async {
      final dio = Dio()..httpClientAdapter = _HangingAdapter();
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
      final dio = Dio()..httpClientAdapter = _CancelableAdapter();
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

ResponseBody _response(
  String body, {
  int statusCode = 200,
  List<String>? setCookies,
}) {
  final headers = <String, List<String>>{
    Headers.contentTypeHeader: ['text/html; charset=utf-8'],
  };
  if (setCookies != null) headers['set-cookie'] = setCookies;
  return ResponseBody.fromString(body, statusCode, headers: headers);
}

String? _headerValue(RequestOptions options, String name) {
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value?.toString();
    }
  }
  return null;
}

class _FakeAdapter implements HttpClientAdapter {
  _FakeAdapter(this.responses);

  final List<ResponseBody> responses;
  final List<RequestOptions> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    if (responses.isEmpty) {
      throw StateError('没有更多伪造响应');
    }
    return responses.removeAt(0);
  }

  @override
  void close({bool force = false}) {}
}

class _HangingAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    return Completer<ResponseBody>().future;
  }

  @override
  void close({bool force = false}) {}
}

class _CancelableAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    final completer = Completer<ResponseBody>();
    cancelFuture?.whenComplete(() {
      if (completer.isCompleted) return;
      completer.completeError(
        DioException.requestCancelled(
          requestOptions: options,
          reason: 'test cancel',
        ),
      );
    });
    return completer.future;
  }

  @override
  void close({bool force = false}) {}
}

String _htmlFor(Map<String, dynamic> root) =>
    '<script>window._ROUTER_DATA = ${jsonEncode(root)};</script>';

Map<String, dynamic> _imagePostRoot() => {
      'loaderData': {
        'note_(id)/page': {
          'videoInfoRes': {
            'item_list': [
              {
                'aweme_id': '123',
                'images': [
                  {
                    'url_list': [
                      'https://p3.douyinpic.com/a.webp',
                      'https://p3.douyinpic.com/a.jpeg',
                    ],
                    'width': 1080,
                    'height': 1440,
                  },
                  {
                    'url_list': ['https://p3.douyinpic.com/b.jpeg'],
                    'width': 1080,
                    'height': 1440,
                    'video': {
                      'play_addr': {
                        'url_list': ['https://v.douyin.com/live.mp4'],
                        'width': 1080,
                        'height': 1920,
                        'data_size': 12345,
                      },
                    },
                  },
                ],
              },
            ],
          },
        },
      },
    };

Map<String, dynamic> _videoRoot() => {
      'loaderData': {
        'video_(id)/page': {
          'videoInfoRes': {
            'item_list': [
              {
                'aweme_id': '456',
                'video': {
                  'bit_rate': [
                    {
                      'bit_rate': 850000,
                      'gear_name': '720p',
                      'play_addr': {
                        'url_list': ['https://cdn.example.com/720.mp4'],
                        'width': 720,
                        'height': 1280,
                        'data_size': 5000000,
                      },
                    },
                    {
                      'bit_rate': 2800000,
                      'gear_name': '1080p',
                      'play_addr': {
                        'url_list': ['https://cdn.example.com/1080.mp4'],
                        'width': 1080,
                        'height': 1920,
                        'data_size': 14000000,
                      },
                    },
                    {
                      'bit_rate': 500000,
                      'gear_name': 'dash',
                      'format': 'dash',
                      'play_addr': {
                        'url_list': ['https://cdn.example.com/dash.mp4'],
                      },
                    },
                    {
                      'bit_rate': 2800000,
                      'gear_name': '1080p',
                      'play_addr': {
                        'url_list': ['https://cdn.example.com/1080.mp4'],
                        'width': 1080,
                        'height': 1920,
                        'data_size': 14000000,
                      },
                    },
                  ],
                },
              },
            ],
          },
        },
      },
    };
