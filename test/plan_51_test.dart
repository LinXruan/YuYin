import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/url_parser.dart';

void main() {
  group('PLAN_51: 抖音主页作品数量 Tag 捕获单元测试', () {
    test('读取 sources/164_抖音主页链接 样本文件验证 3 个样本链接', () {
      File sampleFile = File('sources/164/主页链接.txt');
      if (!sampleFile.existsSync()) {
        sampleFile = File('sources/164_抖音主页链接/主页链接.txt');
      }
      if (!sampleFile.existsSync()) {
        sampleFile = File('sources/164_抖音主页链接/151个作品的主页链接.txt');
      }
      expect(sampleFile.existsSync(), isTrue);

      final content = sampleFile.readAsStringSync();
      expect(content.contains('151个作品数量：'), isTrue);
      expect(content.contains('1150个作品数量：'), isTrue);
      expect(content.contains('63个作品数量：'), isTrue);

      final lines = content.split('\n').map((l) => l.trim()).toList();
      for (final line in lines) {
        if (line.isEmpty) continue;
        final url = UrlParser.extractDouyinUrl(line);
        expect(url, isNotNull);
        expect(UrlParser.isUserHomeUrl(url), isTrue);
        expect(UrlParser.extractSecUid(url), isNotNull);
      }
    });

    test('UserHomeResult worksTotalTag 与 tabCount 属性校验', () {
      const r1 = UserHomeResult(
        secUid: 'uid1',
        nickname: '哈姆雷子',
        workUrls: ['https://www.douyin.com/video/1'],
        tabCount: 151,
      );
      expect(r1.tabCount, 151);
      expect(r1.worksTotalTag, 151);
      expect(r1.count, 1);
      expect(r1.toMap()['worksTotalTag'], 151);
      expect(r1.toMap()['tabCount'], 151);

      const r2 = UserHomeResult(
        secUid: 'uid2',
        nickname: '铁根er',
        workUrls: [],
        tabCount: 1150,
      );
      expect(r2.worksTotalTag, 1150);

      const r3 = UserHomeResult(
        secUid: 'uid3',
        nickname: '世茹很如意',
        workUrls: [],
        tabCount: 63,
      );
      expect(r3.worksTotalTag, 63);

      const rEmpty = UserHomeResult(
        secUid: 'uid0',
        nickname: '测试',
        workUrls: [],
      );
      expect(rEmpty.tabCount, isNull);
      expect(rEmpty.worksTotalTag, 0);
    });
  });
}
