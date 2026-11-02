import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/douyin_share_api.dart';
import 'package:yuyin/services/sniffer/quality_resolution_policy.dart';

void main() {
  group('QualityResolutionPolicy 画质决策策略测试', () {
    late QualityResolutionPolicy policy;

    setUp(() {
      policy = QualityResolutionPolicy(
        qualityWaitWindow: const Duration(milliseconds: 100),
      );
    });

    tearDown(() {
      policy.dispose();
    });

    final dummyResult = DouyinShareResult(
      isImagePost: false,
      title: '测试视频',
      items: const [
        MediaItem(
          url: 'https://example.com/video.mp4',
          type: MediaType.video,
        ),
      ],
    );

    test('未登录状态下分享页视频到达：立即决议采纳，零延迟完成', () {
      var timeoutCalled = false;
      final action = policy.onShareVideoArrived(
        result: dummyResult,
        isLoggedIn: false,
        onWaitTimeout: () => timeoutCalled = true,
      );

      expect(action, QualityResolutionAction.immediateResolve);
      expect(timeoutCalled, isFalse);
    });

    test('已登录状态下分享页视频到达：启动有界等待窗口，暂存兜底', () async {
      var timeoutCalled = false;
      final action = policy.onShareVideoArrived(
        result: dummyResult,
        isLoggedIn: true,
        onWaitTimeout: () => timeoutCalled = true,
      );

      expect(action, QualityResolutionAction.scheduleQualityWait);
      expect(policy.hasCachedFallback, isTrue);
      expect(policy.cachedFallback?.title, '测试视频');
      expect(timeoutCalled, isFalse);

      // 等待窗口期满
      await Future<void>.delayed(const Duration(milliseconds: 150));
      expect(timeoutCalled, isTrue);
      expect(
        policy.onWindowTimeoutTriggered(),
        QualityResolutionAction.resolveWithCachedFallback,
      );
    });

    test('窗口期内主 WebView 提取到更高码率：成功晋升，取消兜底等待', () async {
      var timeoutCalled = false;
      policy.onShareVideoArrived(
        result: dummyResult,
        isLoggedIn: true,
        onWaitTimeout: () => timeoutCalled = true,
      );

      // 50ms 内主 WebView 提取完成
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final webAction = policy.onWebVideoExtracted();

      expect(webAction, QualityResolutionAction.upgradeWithWebResult);

      // 窗口到期后不再触发超时
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(timeoutCalled, isFalse);
    });

    test('遭遇登录墙或会话失效：立即打断等待，闪电决议兜底结果', () {
      var timeoutCalled = false;
      policy.onShareVideoArrived(
        result: dummyResult,
        isLoggedIn: true,
        onWaitTimeout: () => timeoutCalled = true,
      );

      final wallAction = policy.onLoginWallOrInvalidated();
      expect(wallAction, QualityResolutionAction.resolveWithCachedFallback);
      expect(timeoutCalled, isFalse);
    });

    test('reset 后状态完全清空', () {
      policy.onShareVideoArrived(
        result: dummyResult,
        isLoggedIn: true,
        onWaitTimeout: () {},
      );
      expect(policy.hasCachedFallback, isTrue);

      policy.reset();
      expect(policy.hasCachedFallback, isFalse);
      expect(policy.cachedFallback, isNull);
    });
  });
}
