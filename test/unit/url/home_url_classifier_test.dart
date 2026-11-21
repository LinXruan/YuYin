import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/user_home/user_home_result.dart';
import 'package:yuyin/models/url/douyin_link_kind.dart';
import 'package:yuyin/utils/url/url_classifier.dart';
import 'package:yuyin/utils/url/url_extractor.dart';

void main() {
  group('PLAN_50: 抖音主页链接捕获与登录守卫单元测试', () {
    const sampleHomeUrl =
        'https://www.douyin.com/user/MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g?from_tab_name=main&vid=7701683319334910554';
    const sampleSecUid =
        'MS4wLjABAAAAVKdwm0VboixgMdyotVl-8jTDdimg5wXZ4c0wSTHOu6FTSKUrAWG6gIqfJC8Eti-g';

    test('DouyinUrlClassifier.isUserHomeUrl 精确识别主页链接', () {
      expect(DouyinUrlClassifier.isUserHomeUrl(sampleHomeUrl), isTrue);
      expect(
        DouyinUrlClassifier.isUserHomeUrl('https://www.douyin.com/user/$sampleSecUid'),
        isTrue,
      );
      expect(
        DouyinUrlClassifier.isUserHomeUrl('https://www.douyin.com/user/$sampleSecUid#tab'),
        isTrue,
      );

      // 非主页链接测试
      expect(
        DouyinUrlClassifier.isUserHomeUrl('https://www.douyin.com/video/7391965576757628212'),
        isFalse,
      );
      expect(
        DouyinUrlClassifier.isUserHomeUrl('https://www.douyin.com/note/7701683319334910554'),
        isFalse,
      );
      expect(
        DouyinUrlClassifier.isUserHomeUrl('https://www.douyin.com/article/7697159257049500763'),
        isFalse,
      );
      expect(DouyinUrlClassifier.isUserHomeUrl(null), isFalse);
      expect(DouyinUrlClassifier.isUserHomeUrl(''), isFalse);
    });

    test('DouyinUrlExtractor.extractSecUid 准确提取 sec_uid', () {
      expect(DouyinUrlExtractor.extractSecUid(sampleHomeUrl), sampleSecUid);
      expect(
        DouyinUrlExtractor.extractSecUid('https://www.douyin.com/user/abc123456?a=1'),
        'abc123456',
      );
      expect(
        DouyinUrlExtractor.extractSecUid('https://www.douyin.com/video/7391965576757628212'),
        isNull,
      );
    });

    test('DouyinUrlClassifier.classifyWorkPage 识别主页链接为 userHome', () {
      expect(
        DouyinUrlClassifier.classifyWorkPage(sampleHomeUrl),
        DouyinWorkPage.userHome,
      );
    });

    test('UserHomeResult 基础属性与 toMap 序列化正确', () {
      const result = UserHomeResult(
        secUid: sampleSecUid,
        nickname: '琳玄染',
        workUrls: [
          'https://www.douyin.com/note/7701683319334910554',
          'https://www.douyin.com/video/7699742794776932454',
        ],
        tabCount: 15,
      );

      expect(result.secUid, sampleSecUid);
      expect(result.nickname, '琳玄染');
      expect(result.count, 2);
      expect(result.tabCount, 15);

      final map = result.toMap();
      expect(map['secUid'], sampleSecUid);
      expect(map['nickname'], '琳玄染');
      expect(map['count'], 2);
      expect(map['tabCount'], 15);
      expect(map['workUrls'], hasLength(2));
    });

    test('读取 sources/163_抖音主页链接 样本文件验证 15 条作品格式', () {
      File sampleFile = File('sources/163/主页以及其作品链接');
      if (!sampleFile.existsSync()) {
        sampleFile = File('sources/163_抖音主页链接/主页以及其作品链接');
      }
      expect(sampleFile.existsSync(), isTrue);

      final lines = sampleFile
          .readAsLinesSync()
          .map((l) => l.trim())
          .where((l) => l.isNotEmpty)
          .toList();

      expect(lines.first.startsWith('主页链接：'), isTrue);
      final homeUrl = lines.first.substring('主页链接：'.length).trim();
      expect(DouyinUrlClassifier.isUserHomeUrl(homeUrl), isTrue);

      // 第一行是主页链接，后续 http 开头的行均为作品链接
      final works = lines.where((l) => l.startsWith('http')).toList();
      expect(works.length, 15);

      for (final w in works) {
        expect(
          w.contains('/video/') || w.contains('/note/') || w.contains('/article/'),
          isTrue,
        );
      }
    });
  });
}
