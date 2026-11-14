import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/bridge/server/agent_automation_server.dart';
import 'package:yuyin/services/script/douyin/douyin_sniff_script.dart';
import 'package:yuyin/utils/debug/log_controller.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PLAN_56: 主页作者头像与昵称捕获算法与模型测试', () {
    test('1. UserHomeProfile 与 UserHomeResult 数据模型完美支持 avatarUrl 与 profile 属性', () {
      const profile = UserHomeProfile(
        secUid: 'MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04',
        nickname: '宁采君',
        avatarUrl:
            'https://p3-pc.douyinpic.com/img/aweme-avatar/tos-cn-i-0813_osIMyzAvEiznnjAA6W1AXBRCSIQHN0AfgASiCe~c5_300x300.jpeg?from=2956013662',
      );

      expect(profile.isValid, isTrue);
      expect(profile.secUid, 'MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04');
      expect(profile.nickname, '宁采君');
      expect(profile.avatarUrl.contains('aweme-avatar'), isTrue);

      final pMap = profile.toMap();
      final pFromMap = UserHomeProfile.fromMap(pMap);
      expect(pFromMap.nickname, profile.nickname);
      expect(pFromMap.avatarUrl, profile.avatarUrl);

      const homeResult = UserHomeResult(
        secUid: 'MS4wLjABAAAA8YYeky7_h9eHILUHN6UF3mUatKki7QS81NMfbzLHO04',
        nickname: '宁采君',
        avatarUrl:
            'https://p3-pc.douyinpic.com/img/aweme-avatar/tos-cn-i-0813_osIMyzAvEiznnjAA6W1AXBRCSIQHN0AfgASiCe~c5_300x300.jpeg?from=2956013662',
        workUrls: ['https://www.douyin.com/video/12345678901'],
      );

      expect(homeResult.avatarUrl, profile.avatarUrl);
      expect(homeResult.profile.nickname, '宁采君');
      expect(homeResult.profile.avatarUrl, profile.avatarUrl);
      expect(homeResult.toMap()['avatarUrl'], profile.avatarUrl);
    });

    test('2. JS 嗅探脚本包含 pickAuthorAvatar、tryExtractFromUserProfileJson 与 DOM 提取逻辑', () {
      expect(kDouyinSniffJs.contains('pickAuthorAvatar('), isTrue);
      expect(kDouyinSniffJs.contains('tryExtractFromUserProfileJson('), isTrue);
      expect(kDouyinSniffJs.contains('scanUserProfileDom('), isTrue);
      expect(kDouyinSniffJs.contains('maybeReportUserProfile('), isTrue);
      expect(kDouyinSniffJs.contains('user_profile_result'), isTrue);
      expect(kDouyinSniffJs.contains('avatarUrl:'), isTrue);
      expect(kDouyinSniffJs.contains('S.authorAvatar'), isTrue);
      expect(kDouyinSniffJs.contains('aweme-avatar'), isTrue);
    });

    test('3. 169 样本资源对照表完整性与合法性校验', () {
      final sampleDoc = File('sources/169/主页头像与昵称.md');
      expect(sampleDoc.existsSync(), isTrue, reason: 'sources/169/主页头像与昵称.md 必须存在');

      final content = sampleDoc.readAsStringSync();
      expect(content.contains('宁采君'), isTrue);
      expect(content.contains('药厂人家'), isTrue);
      expect(content.contains('腿祖宗.Ann'), isTrue);

      expect(AgentAutomationServer.kReference169Profiles.length, 3);
      for (final profile in AgentAutomationServer.kReference169Profiles) {
        expect(profile['nickname']?.isNotEmpty, isTrue);
        expect(profile['secUid']?.isNotEmpty, isTrue);
        expect(profile['url']?.startsWith('https://www.douyin.com/user/'), isTrue);
        expect(profile['avatarUri']?.isNotEmpty, isTrue);

        final localAvatar = File(profile['avatarFile']!);
        expect(localAvatar.existsSync(), isTrue, reason: '本地头像文件应存在: ${profile['avatarFile']}');
      }
    });
  });

  group('PLAN_56: Debug 自动化接口头像与昵称比对验证 (AgentAutomationServer)', () {
    late AgentAutomationServer server;
    late LogController logs;
    const testPort = 9880;

    setUp(() async {
      HttpOverrides.global = null;
      logs = LogController();
      server = AgentAutomationServer(
        logs: logs,
        busy: ValueNotifier(false),
        loggedIn: ValueNotifier(false),
        port: testPort,
      );
      await server.start();
    });

    tearDown(() async {
      await server.stop();
      HttpOverrides.global = null;
    });

    test('4. 未执行解析时调用 /api/verify/home-profile 返回 400', () async {
      final client = HttpClient();
      final req = await client.post('127.0.0.1', testPort, '/api/verify/home-profile');
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.badRequest);

      final json = jsonDecode(await utf8.decodeStream(resp));
      expect(json['code'], 400);
      expect(json['error'].toString().contains('尚未执行主页解析'), isTrue);
      client.close();
    });

    test('5. 注入标准样本数据后调用 /api/verify/home-profile 精准比对通过', () async {
      for (final sample in AgentAutomationServer.kReference169Profiles) {
        server.setLastUserHomeProfileForTesting(UserHomeProfile(
          secUid: sample['secUid']!,
          nickname: sample['nickname']!,
          avatarUrl: 'https://p3-pc.douyinpic.com/img/aweme-avatar/${sample['avatarUri']}~c5_300x300.jpeg',
        ));

        final client = HttpClient();
        final req = await client.post('127.0.0.1', testPort, '/api/verify/home-profile');
        final resp = await req.close();
        expect(resp.statusCode, HttpStatus.ok);

        final json = jsonDecode(await utf8.decodeStream(resp));
        expect(json['status'], 'ok');
        expect(json['matched'], isTrue);
        expect(json['hasNickname'], isTrue);
        expect(json['hasAvatar'], isTrue);
        expect(json['nickname'], sample['nickname']);
        expect(json['nicknameMatched'], isTrue);
        expect(json['avatarUriMatched'], isTrue);
        client.close();
      }
    });

    test('6. GET /api/status 正常返回 lastUserHomeProfile 与 avatarUrl', () async {
      const testProfile = UserHomeProfile(
        secUid: 'test_sec_uid',
        nickname: '测试昵称',
        avatarUrl: 'https://p3-pc.douyinpic.com/img/aweme-avatar/tos-test.jpeg',
      );
      server.setLastUserHomeProfileForTesting(testProfile);

      final client = HttpClient();
      final req = await client.get('127.0.0.1', testPort, '/api/status');
      final resp = await req.close();
      expect(resp.statusCode, HttpStatus.ok);

      final json = jsonDecode(await utf8.decodeStream(resp));
      expect(json['lastUserHomeProfile'], isNotNull);
      expect(json['lastUserHomeProfile']['nickname'], '测试昵称');
      expect(json['lastUserHomeProfile']['avatarUrl'], 'https://p3-pc.douyinpic.com/img/aweme-avatar/tos-test.jpeg');
      client.close();
    });
  });
}
