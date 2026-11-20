import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/share/client/douyin_share_api.dart';

import 'share_api_fixtures.dart';

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
          DouyinShareApi.parseShareHtml(htmlFor(imagePostRoot()), '123');
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
          DouyinShareApi.parseShareHtml(htmlFor(rootWithMusic), '789');
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
          DouyinShareApi.parseShareHtml(htmlFor(rootWithVideoBgm), '790');
      expect(result2, isNotNull);
      expect(result2!.isImagePost, isTrue);
      expect(result2.imageCount, 1);
      expect(result2.audioCount, 1);
      expect(result2.items.last.type, MediaType.audio);
      expect(result2.items.last.url, contains('aweme/v1/play'));
    });

    test('视频多档位排序、跳过 dash、按档位名去重', () {
      final result =
          DouyinShareApi.parseShareHtml(htmlFor(videoRoot()), '456');
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
      final result = DouyinShareApi.parseShareHtml(htmlFor(root), '123');
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
      final result = DouyinShareApi.parseShareHtml(htmlFor(root), '789');
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
      final result = DouyinShareApi.parseShareHtml(htmlFor(root), '888');
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
      final result = DouyinShareApi.parseShareHtml(htmlFor(root), '889');
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
      final result = DouyinShareApi.parseShareHtml(htmlFor(root), '456');
      expect(result, isNotNull);
      expect(result!.items.single.url, contains('target.mp4'));
    });

    test('风控页/空 item_list/无媒体返回 null', () {
      expect(
        DouyinShareApi.parseShareHtml(
          htmlFor({
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
          htmlFor({
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
          htmlFor({
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

}