import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/selection_mode_store.dart';

void main() {
  setUp(() {
    SelectionModeStore.reset();
  });

  group('SelectionModeStore 标签级状态机与转移规则测试', () {
    test('初始判断值 a 每个标签（图片、实况、音频）均默认为 1（全选）', () {
      expect(SelectionModeStore.getMode(MediaType.image), 1);
      expect(SelectionModeStore.getMode(MediaType.video), 1);
      expect(SelectionModeStore.getMode(MediaType.audio), 1);
    });

    test('calculateB 正确映射全选(1)、全不选(2)、半选(3)', () {
      // 全选
      expect(SelectionModeStore.calculateB(4, 4), 1);
      expect(SelectionModeStore.calculateB(1, 1), 1);

      // 全不选
      expect(SelectionModeStore.calculateB(0, 4), 2);
      expect(SelectionModeStore.calculateB(0, 1), 2);

      // 半选
      expect(SelectionModeStore.calculateB(1, 4), 3);
      expect(SelectionModeStore.calculateB(2, 4), 3);
      expect(SelectionModeStore.calculateB(3, 4), 3);

      // 异常保护：total <= 0
      expect(SelectionModeStore.calculateB(0, 0), 1);
    });

    test('单标签独立状态转移：针对音频标签的流转，不影响图片与实况', () {
      // 初始均为 1
      expect(SelectionModeStore.getMode(MediaType.audio), 1);
      expect(SelectionModeStore.getMode(MediaType.image), 1);

      // 1. 本次音频全都不选 (b = 2) -> 音频 a = 2，图片不受影响
      SelectionModeStore.recordCategorySelection(MediaType.audio, 2);
      expect(SelectionModeStore.getMode(MediaType.audio), 2);
      expect(SelectionModeStore.getMode(MediaType.image), 1);
      expect(SelectionModeStore.getMode(MediaType.video), 1);

      // 2. 本次音频半选 (b = 3) -> 音频 a 保持不变 (仍为 2)
      SelectionModeStore.recordCategorySelection(MediaType.audio, 3);
      expect(SelectionModeStore.getMode(MediaType.audio), 2);

      // 3. 本次音频全选 (b = 1) -> 音频 a 切换回 1
      SelectionModeStore.recordCategorySelection(MediaType.audio, 1);
      expect(SelectionModeStore.getMode(MediaType.audio), 1);
    });

    test('updateFromSheetItems 依据当前资源列表分别结算各标签状态', () {
      const items = [
        MediaItem(url: 'https://example.com/img1.jpg', type: MediaType.image), // 0
        MediaItem(url: 'https://example.com/img2.jpg', type: MediaType.image), // 1
        MediaItem(url: 'https://example.com/live.mp4', type: MediaType.video), // 2
        MediaItem(url: 'https://example.com/bgm.m4a', type: MediaType.audio),  // 3
      ];

      // 场景 1：图片全选 (0, 1)，实况全选 (2)，音频全不选 (不含 3)
      SelectionModeStore.updateFromSheetItems(
        allItems: items,
        selectedIndices: {0, 1, 2},
      );
      expect(SelectionModeStore.getMode(MediaType.image), 1); // 2/2 -> b=1 -> a=1
      expect(SelectionModeStore.getMode(MediaType.video), 1); // 1/1 -> b=1 -> a=1
      expect(SelectionModeStore.getMode(MediaType.audio), 2); // 0/1 -> b=2 -> a=2

      // 场景 2：图片半选 (仅勾选 0)，实况全不选，音频仍全不选
      SelectionModeStore.updateFromSheetItems(
        allItems: items,
        selectedIndices: {0},
      );
      expect(SelectionModeStore.getMode(MediaType.image), 1); // 1/2 -> b=3 -> a保持1
      expect(SelectionModeStore.getMode(MediaType.video), 2); // 0/1 -> b=2 -> a变为2
      expect(SelectionModeStore.getMode(MediaType.audio), 2); // 0/1 -> b=2 -> a保持2

      // 场景 3：新作品中缺少实况与音频，仅有图片
      const imagesOnly = [
        MediaItem(url: 'https://example.com/a.jpg', type: MediaType.image),
        MediaItem(url: 'https://example.com/b.jpg', type: MediaType.image),
      ];
      // 用户全都不选图片
      SelectionModeStore.updateFromSheetItems(
        allItems: imagesOnly,
        selectedIndices: {},
      );
      expect(SelectionModeStore.getMode(MediaType.image), 2); // 0/2 -> a变为2
      // 实况与音频在此次作品中不存在，状态保持原样 (均为 2)
      expect(SelectionModeStore.getMode(MediaType.video), 2);
      expect(SelectionModeStore.getMode(MediaType.audio), 2);

      // 场景 4：重置
      SelectionModeStore.reset();
      expect(SelectionModeStore.getMode(MediaType.image), 1);
      expect(SelectionModeStore.getMode(MediaType.video), 1);
      expect(SelectionModeStore.getMode(MediaType.audio), 1);
    });
  });
}
