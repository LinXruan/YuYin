import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/services/login_detector_script.dart';
import 'package:yuyin/utils/login_state_store.dart';

void main() {
  group('extractStrictUserFromJson 正向鉴权用例', () {
    test('解析 aweme user profile self 官方个人凭证', () {
      final json = {
        'status_code': 0,
        'user': {
          'uid': '9876543210',
          'sec_uid': 'MS4wLjABAAAA_mock_sec_uid',
        },
      };
      final profile =
          extractStrictUserFromJson(json, source: 'probe_profile');
      expect(profile, isNotNull);
      expect(profile!.userId, '9876543210');
      expect(profile.source, 'probe_profile');
    });

    test('解析 passport account 凭证数据', () {
      final json = {
        'message': 'success',
        'data': {
          'user_id': '1092837465',
        },
      };
      final profile =
          extractStrictUserFromJson(json, source: 'probe_account');
      expect(profile, isNotNull);
      expect(profile!.userId, '1092837465');
      expect(profile.source, 'probe_account');
    });
  });

  group('extractStrictUserFromJson 反例防误判防线', () {
    test('获取二维码接口响应必须返回 null', () {
      final qrcodeJson = {
        'message': 'success',
        'data': {
          'qrcode': 'data:image/png;base64,iVBORw0KG...',
          'token': 'mock_token_123',
        },
      };
      expect(extractStrictUserFromJson(qrcodeJson), isNull);
    });

    test('未登录状态返回 user_id=0 时必须返回 null', () {
      final unloggedJson = {
        'message': 'error',
        'data': {
          'user_id': 0,
          'description': '用户未登录',
          'error_code': 101,
        },
      };
      expect(extractStrictUserFromJson(unloggedJson), isNull);
    });

    test('包含明确未登录 description 时必须返回 null', () {
      final notLoginJson = {
        'message': 'error',
        'data': {
          'description': 'session expired, 用户未登录',
        },
      };
      expect(extractStrictUserFromJson(notLoginJson), isNull);
    });

    test('status_code 非 0 的 profile 接口必须返回 null', () {
      final errorProfile = {
        'status_code': 2048,
        'user': null,
      };
      expect(extractStrictUserFromJson(errorProfile), isNull);
    });
  });

  group('parseLoginChannelMessage 通道消息与登出协议测试', () {
    test('解析 logout_event 退出登录事件', () {
      const logoutMessage = '{"type":"logout_event","source":"hook_logout"}';
      final event = parseLoginChannelMessage(logoutMessage);
      expect(event, isNotNull);
      expect(event!.type, LoginEventType.logoutEvent);
      expect(event.profile, isNull);
    });

    test('解析 login_success 有效登录事件', () {
      const loginMessage = '''
      {
        "type": "login_success",
        "source": "probe_account",
        "user": {
          "userId": "1092837465"
        }
      }
      ''';
      final event = parseLoginChannelMessage(loginMessage);
      expect(event, isNotNull);
      expect(event!.type, LoginEventType.loginSuccess);
      expect(event.profile?.userId, '1092837465');
    });

    test('缺少合法数字 userId 时必须拦截', () {
      const badMessage = '{"type":"login_success","user":{"userId":"0"}}';
      expect(parseLoginChannelMessage(badMessage), isNull);
    });
  });

  group('kDouyinLoginDetectJs 静态特征检查', () {
    test('包含登出监听与严格鉴权特征，无昵称抓取', () {
      expect(kDouyinLoginDetectJs, contains('logout_event'));
      expect(kDouyinLoginDetectJs, contains('login_success'));
      expect(kDouyinLoginDetectJs, contains('extractStrictUser'));
      expect(kDouyinLoginDetectJs.contains('nickname'), isFalse);
    });
  });

  group('LoginStateStore.hasLoginSession Cookie 会话检测', () {
    test('空 Cookie 或仅游客 Cookie 必须判定为未登录', () {
      expect(LoginStateStore.hasLoginSession(''), isFalse);
      expect(
        LoginStateStore.hasLoginSession('ttwid=1%7Cabc; odin_tt=mock123; passport_csrf_token_default=abc'),
        isFalse,
      );
    });

    test('包含 sessionid / sessionid_ss / sid_guard 等正式会话判定为已登录', () {
      expect(
        LoginStateStore.hasLoginSession('ttwid=1%7Cabc; sessionid=mock_session_val; odin_tt=123'),
        isTrue,
      );
      expect(
        LoginStateStore.hasLoginSession('sessionid_ss=mock_session_ss_val; passport_csrf_token=123'),
        isTrue,
      );
      expect(
        LoginStateStore.hasLoginSession('sid_guard=mock_guard_token; uid_tt=12345'),
        isTrue,
      );
    });
  });
}
