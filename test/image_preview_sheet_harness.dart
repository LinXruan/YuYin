import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/media/audio_preview_service.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/widgets/save_page/bottom_media_sheet.dart';

// 1x1 像素透明 PNG 二进制数据，避免测试环境下的真实网络请求
const _transparentImageBytes = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, 0x49,
  0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, 0x08, 0x06,
  0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, 0x0A, 0x49, 0x44,
  0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, 0x0D,
  0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42,
  0x60, 0x82
];

class _TestHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _MockHttpClient();
}

class _MockHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;
  @override
  Duration? connectionTimeout;
  @override
  Duration idleTimeout = const Duration(seconds: 15);
  @override
  int? maxConnectionsPerHost;
  @override
  String? userAgent;

  @override
  void addCredentials(Uri url, String realm, HttpClientCredentials credentials) {}
  @override
  void addProxyCredentials(String host, int port, String realm, HttpClientCredentials credentials) {}
  @override
  set authenticate(Future<bool> Function(Uri url, String scheme, String? realm)? f) {}
  @override
  set authenticateProxy(Future<bool> Function(String host, int port, String scheme, String? realm)? f) {}
  @override
  set badCertificateCallback(bool Function(X509Certificate cert, String host, int port)? callback) {}
  @override
  void close({bool force = false}) {}
  @override
  set findProxy(String Function(Uri url)? f) {}

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _MockHttpClientRequest();
  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _MockHttpClientRequest();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _MockHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _MockHttpClientResponse();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpHeaders implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  void set(String name, Object value, {bool preserveHeaderCase = false}) {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MockHttpClientResponse implements HttpClientResponse {
  @override
  int get statusCode => 200;
  @override
  int get contentLength => _transparentImageBytes.length;
  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(_transparentImageBytes).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void installHttpOverrides() {
  HttpOverrides.global = _TestHttpOverrides();
}

const testItems = [
  MediaItem(url: 'https://example.com/img1.jpg', type: MediaType.image),
  MediaItem(url: 'https://example.com/img2.jpg', type: MediaType.image),
  MediaItem(url: 'https://example.com/live.mp4', type: MediaType.video),
  MediaItem(
    url: 'https://example.com/bgm.m4a',
    type: MediaType.audio,
    gearName: '配乐音频',
  ),
];

Widget buildPreviewWidget({
  required List<MediaItem> items,
  Brightness brightness = Brightness.light,
  AudioPreviewService? audioService,
  TerminalSeed seed = const TerminalSeed(),
}) {
  final work = SaveWorkItem(
    url: 'https://example.com/work',
    kind: WorkMediaKind.image,
  );
  final session = SaveSelectionSession.singleWork(
    work: work,
    parsed: SingleWorkResult(
      items: items,
      cookie: '',
      isImagePost: true,
    ),
    seed: seed,
  );
  return MaterialApp(
    theme: ThemeData(brightness: brightness, useMaterial3: true),
    home: Scaffold(
      body: ImagePreviewSheet(
        session: session,
        workUrl: work.url,
        items: items,
        headers: const {'User-Agent': 'Test'},
        audioService: audioService,
      ),
    ),
  );
}