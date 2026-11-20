import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

// 分享接口测试共用夹具：路由数据 HTML、伪造响应与 Dio 适配器。
ResponseBody fakeResponse(
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

String? headerValue(RequestOptions options, String name) {
  for (final entry in options.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value?.toString();
    }
  }
  return null;
}

class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.responses);

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

class HangingAdapter implements HttpClientAdapter {
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

class CancelableAdapter implements HttpClientAdapter {
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

String htmlFor(Map<String, dynamic> root) =>
    '<script>window._ROUTER_DATA = ${jsonEncode(root)};</script>';

Map<String, dynamic> imagePostRoot() => {
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

Map<String, dynamic> videoRoot() => {
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