import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/user_home/user_home_profile.dart';
import 'package:yuyin/models/user_home/user_home_result.dart';
import 'package:yuyin/services/sniffer/lifecycle/sniff_cancelled_exception.dart';
import 'package:yuyin/services/user_home/user_home_extractor.dart';

class _FakeHomeDelegate implements IUserHomeSnifferDelegate {
  _FakeHomeDelegate(this.handler);

  final Future<UserHomeResult> Function(int attempt) handler;
  int calls = 0;

  @override
  Future<UserHomeResult> sniffUserHomeUrl(String homeUrl) {
    calls++;
    return handler(calls);
  }

  @override
  Future<UserHomeProfile> sniffUserProfile(String homeUrl) async {
    return const UserHomeProfile(secUid: 'sec', nickname: '作者');
  }

  @override
  void cancelActiveTask() {}
}

UserHomeResult _homeResult() => const UserHomeResult(
      secUid: 'sec_1',
      nickname: '作者',
      workUrls: ['https://www.douyin.com/video/7300000000000000001'],
      tabCount: 1,
    );

const _homeUrl = 'https://www.douyin.com/user/sec_1';

void main() {
  test('主页超时自动重试一次后成功', () async {
    final delegate = _FakeHomeDelegate((attempt) async {
      if (attempt == 1) throw TimeoutException('主页滚动超时');
      return _homeResult();
    });

    final result = await UserHomeExtractor(delegate).extractAllWorks(_homeUrl);

    expect(result.count, 1);
    expect(delegate.calls, 2);
  });

  test('连续两次超时后上抛', () async {
    final delegate = _FakeHomeDelegate(
      (attempt) async => throw TimeoutException('主页滚动超时'),
    );

    await expectLater(
      UserHomeExtractor(delegate).extractAllWorks(_homeUrl),
      throwsA(isA<TimeoutException>()),
    );
    expect(delegate.calls, 2);
  });

  test('取消不重试', () async {
    final delegate = _FakeHomeDelegate(
      (attempt) async => throw const SniffCancelledException(),
    );

    await expectLater(
      UserHomeExtractor(delegate).extractAllWorks(_homeUrl),
      throwsA(isA<SniffCancelledException>()),
    );
    expect(delegate.calls, 1);
  });
}
