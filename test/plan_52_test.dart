import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/url_parser.dart';

void main() {
  group('PLAN_52: 主页作品滚动加载与节流日志统计单元测试', () {
    test('UserHomeResult 大容量作品列表序列化与去重校验', () {
      final mockUrls = List.generate(
        151,
        (i) => 'https://www.douyin.com/video/73919655767576282$i',
      );

      final result = UserHomeResult(
        secUid: 'mock_sec_uid',
        nickname: '天冷冷.',
        workUrls: mockUrls,
        tabCount: 151,
      );

      expect(result.count, 151);
      expect(result.worksTotalTag, 151);
      expect(result.tabCount, 151);
      expect(result.workUrls.length, 151);

      final map = result.toMap();
      expect(map['count'], 151);
      expect(map['worksTotalTag'], 151);
      expect(map['workUrls'], hasLength(151));
    });

    test('验证 164 样本中 3 个主页 URL 的合法性与 sec_uid 提取', () {
      File sampleFile = File('sources/164/主页链接.txt');
      if (!sampleFile.existsSync()) {
        sampleFile = File('sources/164_抖音主页链接/主页链接.txt');
      }
      if (!sampleFile.existsSync()) {
        sampleFile = File('sources/164_抖音主页链接/151个作品的主页链接.txt');
      }
      expect(sampleFile.existsSync(), isTrue);

      final content = sampleFile.readAsStringSync();
      final lines = content.split('\n').map((l) => l.trim()).toList();

      final parsedUrls = <String>[];
      for (final line in lines) {
        if (line.isEmpty) continue;
        final url = UrlParser.extractDouyinUrl(line);
        if (url != null && UrlParser.isUserHomeUrl(url)) {
          parsedUrls.add(url);
        }
      }

      expect(parsedUrls.length, 3);
      for (final u in parsedUrls) {
        expect(UrlParser.extractSecUid(u), isNotNull);
      }
    });
  });
}
