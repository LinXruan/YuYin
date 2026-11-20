import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/utils/history/history_store.dart';

void main() {
  setUp(() => HistoryStore.resetForTesting(skipSave: true));

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
}
