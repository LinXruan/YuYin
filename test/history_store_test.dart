import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/utils/history/history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('history_store_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (MethodCall methodCall) async {
        return tempDir.path;
      },
    );
  });

  tearDownAll(() async {
    try {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    } catch (_) {}
  });

  setUp(() {
    HistoryStore.resetForTesting();
  });

  group('HistoryItem 数据模型与格式化测试', () {
    test('序列化与反序列化一致性', () {
      final now = DateTime(2026, 11, 2, 14, 30);
      final item = HistoryItem(
        id: 'test_123',
        url: 'https://v.douyin.com/abc1234/',
        rawInput: '分享抖音 https://v.douyin.com/abc1234/',
        fullDesc: '这是一段很长的完整文案，包含很多细节 #抖音 #视频',
        title: '测试视频标题',
        coverUrl: 'https://example.com/cover.jpg',
        isImagePost: false,
        mediaSummary: '高清 1080P · 25.4 MB',
        itemCount: 1,
        createdAt: now,
      );

      final json = item.toJson();
      final restored = HistoryItem.fromJson(json);

      expect(restored.id, item.id);
      expect(restored.url, item.url);
      expect(restored.rawInput, item.rawInput);
      expect(restored.fullDesc, item.fullDesc);
      expect(restored.title, item.title);
      expect(restored.coverUrl, item.coverUrl);
      expect(restored.isImagePost, item.isImagePost);
      expect(restored.mediaSummary, item.mediaSummary);
      expect(restored.itemCount, item.itemCount);
      expect(restored.createdAt, item.createdAt);
    });

    test('isVideoUrl 精确识别视频流地址并排斥合法图片', () {
      expect(HistoryItem.isVideoUrl('https://example.com/play.mp4'), isTrue);
      expect(HistoryItem.isVideoUrl('https://example.com/play.mov'), isTrue);
      expect(HistoryItem.isVideoUrl('https://example.com/live.flv'), isTrue);
      expect(HistoryItem.isVideoUrl('https://iesdouyin.com/aweme/v1/play/?video_id=123'), isTrue);
      expect(HistoryItem.isVideoUrl('https://iesdouyin.com/aweme/v1/playwm/?video_id=123'), isTrue);

      expect(HistoryItem.isVideoUrl('https://p3.douyinpic.com/cover.jpeg'), isFalse);
      expect(HistoryItem.isVideoUrl('https://p3.douyinpic.com/img.png'), isFalse);
      expect(HistoryItem.isVideoUrl('https://p3.douyinpic.com/tos-cn-p-0015/thumb.webp'), isFalse);
      expect(HistoryItem.isVideoUrl(null), isFalse);
      expect(HistoryItem.isVideoUrl(''), isFalse);
    });

    test('构造函数与 fromJson 自动净化错误传入的视频流 coverUrl 为 null', () {
      final item = HistoryItem(
        id: 'bad_cover_id',
        url: 'https://v.douyin.com/bad/',
        fullDesc: '误存视频直链作为封面的条目',
        coverUrl: 'https://iesdouyin.com/aweme/v1/play/?video_id=v0300fg10000',
      );
      expect(item.coverUrl, isNull);

      final json = {
        'id': 'legacy_dirty_id',
        'url': 'https://v.douyin.com/dirty/',
        'fullDesc': '旧版脏数据测试',
        'coverUrl': 'https://cdn.example.com/video.mp4',
      };
      final parsed = HistoryItem.fromJson(json);
      expect(parsed.coverUrl, isNull);
    });

    test('formattedTime 绝对不包含“抖音”二字，并按时间差友好展示', () {
      final now = DateTime.now();

      // 1. 今天
      final todayItem = HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: 'test',
        createdAt: DateTime(now.year, now.month, now.day, 8, 15),
      );
      expect(todayItem.formattedTime, '今天 08:15');
      expect(todayItem.formattedTime.contains('抖音'), isFalse);

      // 2. 昨天
      final yesterday = now.subtract(const Duration(days: 1));
      final yesterdayItem = HistoryItem(
        id: '2',
        url: 'https://v.douyin.com/2/',
        fullDesc: 'test',
        createdAt: DateTime(yesterday.year, yesterday.month, yesterday.day, 22, 59),
      );
      expect(yesterdayItem.formattedTime, '昨天 22:59');
      expect(yesterdayItem.formattedTime.contains('抖音'), isFalse);

      // 3. 往年以前
      final pastItem = HistoryItem(
        id: '3',
        url: 'https://v.douyin.com/3/',
        fullDesc: 'test',
        createdAt: DateTime(2025, 5, 20, 13, 14),
      );
      expect(pastItem.formattedTime, '2025-05-20 13:14');
      expect(pastItem.formattedTime.contains('抖音'), isFalse);
    });
  });

  group('HistoryStore 内存操作与生命周期测试', () {
    test('初始状态为空', () {
      expect(HistoryStore.records, isEmpty);
      expect(HistoryStore.recordsNotifier.value, isEmpty);
    });

    test('addRecord 添加条目并置顶', () async {
      final item1 = HistoryItem(
        id: '1',
        url: 'https://v.douyin.com/1/',
        fullDesc: '第一个作品',
        createdAt: DateTime.now().subtract(const Duration(minutes: 10)),
      );
      final item2 = HistoryItem(
        id: '2',
        url: 'https://v.douyin.com/2/',
        fullDesc: '第二个作品',
        createdAt: DateTime.now(),
      );

      await HistoryStore.addRecord(item1);
      expect(HistoryStore.records.length, 1);
      expect(HistoryStore.records.first.id, '1');

      await HistoryStore.addRecord(item2);
      expect(HistoryStore.records.length, 2);
      expect(HistoryStore.records.first.id, '2'); // 最新置顶
    });

    test('重复解析相同 url 自动去重并更新置顶', () async {
      final item1 = HistoryItem(
        id: 'first_id',
        url: 'https://v.douyin.com/same_url/',
        fullDesc: '旧文案',
        createdAt: DateTime.now().subtract(const Duration(hours: 1)),
      );
      final item2 = HistoryItem(
        id: 'other_id',
        url: 'https://v.douyin.com/other_url/',
        fullDesc: '其他文案',
        createdAt: DateTime.now().subtract(const Duration(minutes: 30)),
      );
      final item3 = HistoryItem(
        id: 'new_id',
        url: 'https://v.douyin.com/same_url/', // 相同 url
        fullDesc: '更新后的新文案',
        createdAt: DateTime.now(),
      );

      await HistoryStore.addRecord(item1);
      await HistoryStore.addRecord(item2);
      expect(HistoryStore.records.length, 2);

      await HistoryStore.addRecord(item3);
      // 总条数仍为 2，并且新记录置顶，旧记录被替换
      expect(HistoryStore.records.length, 2);
      expect(HistoryStore.records.first.id, 'new_id');
      expect(HistoryStore.records.first.fullDesc, '更新后的新文案');
    });

    test('超过 500 条上限自动截断最旧记录', () async {
      for (int i = 0; i < 510; i++) {
        final item = HistoryItem(
          id: 'id_$i',
          url: 'https://v.douyin.com/$i/',
          fullDesc: '文案 $i',
          createdAt: DateTime.now().add(Duration(seconds: i)),
        );
        await HistoryStore.addRecord(item);
      }

      expect(HistoryStore.records.length, HistoryStore.maxHistoryCount);
      expect(HistoryStore.records.first.id, 'id_509');
      // 最旧的前 10 条（id_0 到 id_9）已被淘汰
      expect(HistoryStore.records.any((r) => r.id == 'id_0'), isFalse);
      expect(HistoryStore.records.any((r) => r.id == 'id_9'), isFalse);
      expect(HistoryStore.records.any((r) => r.id == 'id_10'), isTrue);
    });

    test('deleteRecord 删除单条', () async {
      final item1 = HistoryItem(id: '1', url: 'https://v.douyin.com/1/', fullDesc: 'a');
      final item2 = HistoryItem(id: '2', url: 'https://v.douyin.com/2/', fullDesc: 'b');
      await HistoryStore.addRecord(item1);
      await HistoryStore.addRecord(item2);

      await HistoryStore.deleteRecord('1');
      expect(HistoryStore.records.length, 1);
      expect(HistoryStore.records.first.id, '2');
    });

    test('deleteRecords 批量删除', () async {
      for (int i = 1; i <= 5; i++) {
        await HistoryStore.addRecord(
          HistoryItem(id: '$i', url: 'https://v.douyin.com/$i/', fullDesc: 'item $i'),
        );
      }
      expect(HistoryStore.records.length, 5);

      await HistoryStore.deleteRecords({'1', '3', '5'});
      expect(HistoryStore.records.length, 2);
      final remainingIds = HistoryStore.records.map((r) => r.id).toSet();
      expect(remainingIds, {'2', '4'});
    });

    test('clearAll 清空全部记录', () async {
      await HistoryStore.addRecord(HistoryItem(id: '1', url: 'u1', fullDesc: 'a'));
      await HistoryStore.addRecord(HistoryItem(id: '2', url: 'u2', fullDesc: 'b'));
      expect(HistoryStore.records.length, 2);

      await HistoryStore.clearAll();
      expect(HistoryStore.records, isEmpty);
      expect(HistoryStore.recordsNotifier.value, isEmpty);
    });
  });

  group('HistoryStore 高性能搜索算法测试', () {
    setUp(() async {
      final items = [
        HistoryItem(
          id: '1',
          url: 'https://v.douyin.com/1/',
          title: '可爱猫咪的日常',
          fullDesc: '今天小橘猫在阳台晒太阳，超级可爱治愈！#萌宠 #猫咪日常',
        ),
        HistoryItem(
          id: '2',
          url: 'https://v.douyin.com/2/',
          title: '街头美食探索',
          fullDesc: '探店成都巷子里的地道麻辣烫，味道绝了 #美食 #成都',
        ),
        HistoryItem(
          id: '3',
          url: 'https://v.douyin.com/3/',
          title: 'Flutter 极速开发技巧',
          fullDesc: '高效构建跨平台 App 的核心心法与实战经验分享 #编程 #Flutter',
        ),
        HistoryItem(
          id: '4',
          url: 'https://v.douyin.com/4/',
          title: '小橘猫与金毛犬的搞笑日常',
          fullDesc: '家里养了一只小橘猫和金毛，每天都在打架争宠 #宠物 #搞笑日常',
        ),
      ];

      for (final item in items) {
        await HistoryStore.addRecord(item);
      }
    });

    test('空关键字或纯空格返回全部记录', () {
      expect(HistoryStore.search('').length, 4);
      expect(HistoryStore.search('   ').length, 4);
    });

    test('单关键词匹配完整文案中的内容（无论是否在标题中）', () {
      final res = HistoryStore.search('麻辣烫');
      expect(res.length, 1);
      expect(res.first.id, '2');
    });

    test('单关键词匹配标题', () {
      final res = HistoryStore.search('Flutter');
      expect(res.length, 1);
      expect(res.first.id, '3');
    });

    test('多关键词空格分割 AND 逻辑检索', () {
      // 同时包含 "小橘猫" 和 "打架"
      final res = HistoryStore.search('小橘猫 打架');
      expect(res.length, 1);
      expect(res.first.id, '4');

      // 仅包含 "小橘猫" 的有两个 (id: 4 和 id: 1)
      final allCats = HistoryStore.search('小橘猫');
      expect(allCats.length, 2);
    });

    test('大小写无关检索', () {
      final resUpper = HistoryStore.search('FLUTTER');
      expect(resUpper.length, 1);
      expect(resUpper.first.id, '3');
    });

    test('无匹配结果返回空列表', () {
      final res = HistoryStore.search('太空飞船');
      expect(res, isEmpty);
    });

    test('高并发大容量（500 条数据）纯内存极速检索在 10ms 内完成', () async {
      HistoryStore.resetForTesting();
      for (int i = 0; i < 500; i++) {
        await HistoryStore.addRecord(
          HistoryItem(
            id: 'perf_$i',
            url: 'https://v.douyin.com/perf_$i/',
            title: '作品标题 $i',
            fullDesc: '作品完整文案包含一些长文本内容，编号为 $i 随机测试数据 ${i % 10 == 0 ? "目标特征词" : ""}',
          ),
        );
      }

      final stopwatch = Stopwatch()..start();
      for (int i = 0; i < 100; i++) {
        final results = HistoryStore.search('目标特征词');
        expect(results.length, 50); // 500 / 10 = 50
      }
      stopwatch.stop();

      // 100 次搜索总耗时应非常小（远低于 100ms）
      expect(stopwatch.elapsedMilliseconds, lessThan(200));
    });
  });

  group('HistoryStore 文件落盘与读取持久化测试', () {
    test('addRecord 写入文件后，可以通过 init 恢复', () async {
      final t1 = DateTime(2026, 11, 2, 10, 0);
      final t2 = DateTime(2026, 11, 2, 11, 0);
      await HistoryStore.addRecord(
        HistoryItem(
          id: 'persist_1',
          url: 'https://v.douyin.com/p1/',
          fullDesc: '保存项 1',
          createdAt: t1,
        ),
      );
      await HistoryStore.addRecord(
        HistoryItem(
          id: 'persist_2',
          url: 'https://v.douyin.com/p2/',
          fullDesc: '保存项 2',
          createdAt: t2,
        ),
      );

      // 清空内存
      HistoryStore.resetForTesting();
      expect(HistoryStore.records, isEmpty);

      // 重新从文件加载
      await HistoryStore.init();
      expect(HistoryStore.records.length, 2);
      expect(HistoryStore.records[0].id, 'persist_2'); // 最新的在前面
      expect(HistoryStore.records[1].id, 'persist_1');
    });

    test('PLAN_46: markSaved 与 isSaved 状态持久化及重析继承', () async {
      final item = HistoryItem(
        id: 'test_url_1',
        url: 'https://v.douyin.com/u1/',
        fullDesc: '文案1',
        isSaved: false,
      );
      await HistoryStore.addRecord(item);
      expect(HistoryStore.records.first.isSaved, isFalse);

      // 标记为已保存
      await HistoryStore.markSaved('test_url_1', true);
      expect(HistoryStore.records.first.isSaved, isTrue);

      // search onlySaved 过滤
      expect(HistoryStore.search('', onlySaved: true).length, 1);
      expect(HistoryStore.search('', onlySaved: false).length, 1);

      // 重新解析同一 URL，由于旧记录已保存，新 addRecord 自动继承已保存状态
      await HistoryStore.addRecord(
        HistoryItem(
          id: 'test_url_1',
          url: 'https://v.douyin.com/u1/',
          fullDesc: '更新后的文案1',
          isSaved: false,
        ),
      );
      expect(HistoryStore.records.first.isSaved, isTrue);
      expect(HistoryStore.records.first.fullDesc, '更新后的文案1');
    });
  });
}
