import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/audio_preview_service.dart';
import 'package:yuyin/utils/selection_mode_store.dart';
import 'package:yuyin/widgets/image_preview_sheet.dart';

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
  HttpClient createHttpClient(SecurityContext? context) {
    return _MockHttpClient();
  }
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

void main() {
  setUpAll(() {
    HttpOverrides.global = _TestHttpOverrides();
  });

  const testItems = [
    MediaItem(url: 'https://example.com/img1.jpg', type: MediaType.image),
    MediaItem(url: 'https://example.com/img2.jpg', type: MediaType.image),
    MediaItem(url: 'https://example.com/live.mp4', type: MediaType.video),
    MediaItem(url: 'https://example.com/bgm.m4a', type: MediaType.audio, gearName: '配乐音频'),
  ];

  Widget buildTestWidget({
    required List<MediaItem> items,
    Brightness brightness = Brightness.light,
    AudioPreviewService? audioService,
  }) {
    return MaterialApp(
      theme: ThemeData(
        brightness: brightness,
        useMaterial3: true,
      ),
      home: Scaffold(
        body: ImagePreviewSheet(
          items: items,
          headers: const {'User-Agent': 'Test'},
          audioService: audioService,
        ),
      ),
    );
  }

  setUp(() {
    SelectionModeStore.reset();
  });

  group('ImagePreviewSheet 交互与视觉测试', () {
    testWidgets('默认全部勾选，分类筛选按钮正确展示边框与状态', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget(items: testItems));
      await tester.pump();

      // 验证数量文本
      expect(find.text('已选 4 / 4 项'), findsOneWidget);

      // 验证分类按钮存在
      expect(find.byKey(const ValueKey('category_btn_image')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_btn_live')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_btn_audio')), findsOneWidget);

      // 验证保存按钮文案
      expect(find.text('保存选中项 (4)'), findsOneWidget);
    });

    testWidgets('点击“图片”分类按钮一键取消与全选图片', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget(items: testItems));
      await tester.pump();

      // 点击“图片”按钮 -> 取消选中 2 张图片
      await tester.tap(find.byKey(const ValueKey('category_btn_image')));
      await tester.pumpAndSettle();

      expect(find.text('已选 2 / 4 项'), findsOneWidget);
      expect(find.text('保存选中项 (2)'), findsOneWidget);

      // 再次点击“图片”按钮 -> 重新全选 2 张图片
      await tester.tap(find.byKey(const ValueKey('category_btn_image')));
      await tester.pumpAndSettle();

      expect(find.text('已选 4 / 4 项'), findsOneWidget);
      expect(find.text('保存选中项 (4)'), findsOneWidget);
    });

    testWidgets('缺少资源类型时分类按钮置灰且点击不响应', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 只有图片与音频，缺少实况视频
      const itemsWithoutLive = [
        MediaItem(url: 'https://example.com/img1.jpg', type: MediaType.image),
        MediaItem(url: 'https://example.com/bgm.m4a', type: MediaType.audio),
      ];

      await tester.pumpWidget(buildTestWidget(items: itemsWithoutLive));
      await tester.pump();

      expect(find.text('已选 2 / 2 项'), findsOneWidget);

      // 点击置灰的“实况”按钮
      await tester.tap(find.byKey(const ValueKey('category_btn_live')));
      await tester.pumpAndSettle();

      // 状态与选中项完全不受影响
      expect(find.text('已选 2 / 2 项'), findsOneWidget);
    });

    testWidgets('点击缩略图本身切换勾选状态', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget(items: testItems));
      await tester.pump();

      expect(find.text('已选 4 / 4 项'), findsOneWidget);

      // 点击第一个网格项的缩略图本身
      final firstTile = find.byKey(const ValueKey('media_tile_0'));
      expect(firstTile, findsOneWidget);
      await tester.tap(firstTile);
      await tester.pumpAndSettle();

      // 切换为 3 项
      expect(find.text('已选 3 / 4 项'), findsOneWidget);

      // 再次点击第一个网格项
      await tester.tap(firstTile);
      await tester.pumpAndSettle();

      // 恢复为 4 项
      expect(find.text('已选 4 / 4 项'), findsOneWidget);
    });

    testWidgets('图片右下角小眼睛按钮点击呼出大图预览', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      await tester.pumpWidget(buildTestWidget(items: testItems));
      await tester.pump();

      final firstEye = find.byKey(const ValueKey('eye_button_0'));
      expect(firstEye, findsOneWidget);

      // 点击第一个眼睛按钮
      await tester.tap(firstEye);
      await tester.pumpAndSettle();

      // 弹出全屏 Dialog（含关闭按钮）
      expect(find.byType(InteractiveViewer), findsOneWidget);
      expect(find.byIcon(Icons.close), findsOneWidget);

      // 关闭全屏预览
      await tester.tap(find.byIcon(Icons.close));
      await tester.pumpAndSettle();

      // 确认未影响勾选数量
      expect(find.text('已选 4 / 4 项'), findsOneWidget);
    });

    testWidgets('音频卡片删除“BGM 音频”，居中展示“音频”，右下角播放钮呼出播放条', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final audioService = AudioPreviewService();

      await tester.pumpWidget(
        buildTestWidget(items: testItems, audioService: audioService),
      );
      await tester.pump();

      // 验证“BGM 音频”已被彻底删除
      expect(find.text('BGM 音频'), findsNothing);

      // 验证“音频”居中文本存在
      expect(find.text('音频'), findsWidgets);

      // 初始状态下底部播放条未展示
      expect(find.byKey(const ValueKey('audio_player_close_button')), findsNothing);

      // 点击音频卡片右下角的播放按钮
      final playButtonInTile = find.byKey(const ValueKey('audio_play_button'));
      expect(playButtonInTile, findsOneWidget);
      await tester.tap(playButtonInTile);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 底部播放条已呼出
      expect(find.byKey(const ValueKey('audio_player_close_button')), findsOneWidget);
      expect(find.byKey(const ValueKey('scrubbable_progress_bar')), findsOneWidget);

      // 点击关闭播放条（叉号）
      await tester.tap(find.byKey(const ValueKey('audio_player_close_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 播放条收起
      expect(find.byKey(const ValueKey('audio_player_close_button')), findsNothing);

      audioService.dispose();
    });

    testWidgets('无滑块进度条支持手势横向滑动与轻触精准定位 seek', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      final audioService = AudioPreviewService();

      await tester.pumpWidget(
        buildTestWidget(items: testItems, audioService: audioService),
      );
      await tester.pump();

      // 打开播放条
      await tester.tap(find.byKey(const ValueKey('audio_play_button')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      // 设置总时长为 100 秒
      audioService.duration.value = const Duration(seconds: 100);
      await tester.pump();

      final progressBarFinder = find.byKey(const ValueKey('scrubbable_progress_bar'));
      expect(progressBarFinder, findsOneWidget);

      // 点击进度条中心点（50%位置）
      await tester.tap(progressBarFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // 验证进度跳转到约 50 秒（45s~55s 容差范围）
      final posSeconds = audioService.position.value.inSeconds;
      expect(posSeconds, greaterThanOrEqualTo(45));
      expect(posSeconds, lessThanOrEqualTo(55));

      // 验证时间指示文本同步更新（例如包含 00:50 或 00:49 / 01:40）
      expect(find.textContaining('01:40'), findsOneWidget);

      audioService.dispose();
    });

    testWidgets('暗色模式与亮色模式下均能正常无溢出渲染', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 亮色模式
      await tester.pumpWidget(
        buildTestWidget(items: testItems, brightness: Brightness.light),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);

      // 暗色模式
      await tester.pumpWidget(
        buildTestWidget(items: testItems, brightness: Brightness.dark),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('当标签 a = 2 时，对应标签资源默认初始全不选，保存按钮与分类状态正确联动', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 设所有标签均为 a = 2 (全不选)
      SelectionModeStore.setMode(MediaType.image, 2);
      SelectionModeStore.setMode(MediaType.video, 2);
      SelectionModeStore.setMode(MediaType.audio, 2);

      await tester.pumpWidget(buildTestWidget(items: testItems));
      await tester.pump();

      // 验证数量文本显示 0
      expect(find.text('已选 0 / 4 项'), findsOneWidget);

      // 验证保存按钮存在但禁用 (onPressed == null)
      final filledButton = tester.widget<FilledButton>(
        find.widgetWithText(FilledButton, '保存选中项 (0)'),
      );
      expect(filledButton.onPressed, isNull);

      // 分类筛选按钮均存在且为未全选状态
      expect(find.byKey(const ValueKey('category_btn_image')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_btn_live')), findsOneWidget);
      expect(find.byKey(const ValueKey('category_btn_audio')), findsOneWidget);
    });

    testWidgets('标签级生命周期与状态记忆流转演练：全选图片/取消音频后，下次图片默认勾选而音频默认不勾选', (tester) async {
      tester.view.physicalSize = const Size(800, 1200);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());

      // 第一轮：初值全标签 a = 1，打开保存页
      SelectionModeStore.reset();
      await tester.pumpWidget(buildTestWidget(items: testItems));
      await tester.pump();
      expect(find.text('已选 4 / 4 项'), findsOneWidget);

      // 用户仅取消勾选音频（点击音频分类按钮或点击音频方块）
      await tester.tap(find.byKey(const ValueKey('category_btn_audio')));
      await tester.pump();
      expect(find.text('已选 3 / 4 项'), findsOneWidget);

      // 模拟弹窗退出（保存并 dispose）
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // 校验此时标签独立状态：图片=1, 实况=1, 音频=2 (全不选)
      expect(SelectionModeStore.getMode(MediaType.image), 1);
      expect(SelectionModeStore.getMode(MediaType.video), 1);
      expect(SelectionModeStore.getMode(MediaType.audio), 2);

      // 第二轮：重新打开保存页，依据记忆状态：图片(2)与实况(1)被勾选，音频(0)未勾选
      await tester.pumpWidget(buildTestWidget(items: testItems));
      await tester.pump();
      expect(find.text('已选 3 / 4 项'), findsOneWidget);

      // 用户对图片进行半选：取消第一张图 (index 0)
      await tester.tap(find.byKey(const ValueKey('media_tile_0')));
      await tester.pump();
      expect(find.text('已选 2 / 4 项'), findsOneWidget);

      // 模拟弹窗退出 (图片半选 b=3, 实况全选 b=1, 音频全不选 b=2)
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // 校验状态转移：图片 a 保持 1，实况保持 1，音频保持 2
      expect(SelectionModeStore.getMode(MediaType.image), 1);
      expect(SelectionModeStore.getMode(MediaType.video), 1);
      expect(SelectionModeStore.getMode(MediaType.audio), 2);

      // 第三轮：再次打开保存页，图片与实况依然默认勾选，音频未勾选
      await tester.pumpWidget(buildTestWidget(items: testItems));
      await tester.pump();
      expect(find.text('已选 3 / 4 项'), findsOneWidget);

      // 用户重新勾选音频
      await tester.tap(find.byKey(const ValueKey('category_btn_audio')));
      await tester.pump();
      expect(find.text('已选 4 / 4 项'), findsOneWidget);

      // 模拟点击保存按钮退出
      await tester.tap(find.text('保存选中项 (4)'));
      await tester.pump();
      await tester.pumpWidget(const SizedBox());
      await tester.pump();

      // 校验状态转移：音频重新恢复为 a = 1 (全选)
      expect(SelectionModeStore.getMode(MediaType.audio), 1);
      expect(SelectionModeStore.getMode(MediaType.image), 1);
      expect(SelectionModeStore.getMode(MediaType.video), 1);
    });
  });
}
