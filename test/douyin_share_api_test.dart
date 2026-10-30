import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/douyin_share_api.dart';

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
