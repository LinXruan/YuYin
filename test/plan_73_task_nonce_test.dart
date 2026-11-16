import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/script/douyin/chunk/js_home_collect.dart';
import 'package:yuyin/services/script/douyin/chunk/js_home_finish.dart';
import 'package:yuyin/services/script/douyin/douyin_sniff_script.dart';
import 'package:yuyin/services/sniffer/lifecycle/sniff_cancelled_exception.dart';

void main() {
  group('任务 nonce 守卫', () {
    test('脚本按任务归属拒绝旧文档', () {
      expect(kDouyinSniffJs, contains('window.__dyTaskNonce'));
      expect(kDouyinSniffJs, contains('if (!S.nonce) S.nonce'));
      expect(kDouyinSniffJs, contains("S.nonce !== window.__dyTaskNonce"));
      expect(kDouyinSniffJs, contains("location.protocol === 'about:'"));
    });

    test('结果类消息携带 task 与 awemeId', () {
      expect(kDouyinSniffJs, contains('task: S.nonce'));
      expect(kDouyinSniffJs, contains('awemeId: S.targetId'));
      expect(kDouyinSniffJs, contains('type: \'user_home_result\''));
      expect(kDouyinSniffJs, contains('type: \'user_profile_result\''));
    });
  });

  group('主页完成判定', () {
    test('作品总数只增不减', () {
      expect(jsHomeFinish, contains('function updateWorksTabCount'));
      expect(jsHomeFinish, contains('if (tabCount > S.worksTabCount)'));
      expect(jsHomeCollect, isNot(contains('S.worksTabCount = tabCount')));
    });

    test('接口无更多但数量不足时滚动确认', () {
      expect(jsHomeFinish, contains('S.homeIdleScrolls >= 4'));
      expect(jsHomeFinish, contains('function shouldKeepHomeScrolling'));
    });
  });

  test('取消异常保留用户可见文案', () {
    expect(const SniffCancelledException().toString(), '用户已取消解析');
  });
}
