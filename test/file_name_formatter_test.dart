import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/utils/file_name_formatter.dart';

void main() {
  group('FileNameFormatter.sanitize', () {
    test('过滤非法字符并折叠空白', () {
      expect(
        FileNameFormatter.sanitize('探店/火锅:太好吃了? 绝了*<推荐>|必吃"'),
        '探店 火锅 太好吃了 绝了 推荐 必吃',
      );
    });

    test('移除换行符与制表符', () {
      expect(
        FileNameFormatter.sanitize('第一行\n第二行\r\n第三行\t结束'),
        '第一行 第二行 第三行 结束',
      );
    });

    test('去除末尾的连续句号与空白', () {
      expect(
        FileNameFormatter.sanitize('  这是一个很棒的作品...  '),
        '这是一个很棒的作品',
      );
    });
  });

  group('FileNameFormatter.truncate', () {
    test('不足 10 个中文字符不截断也不加省略号', () {
      expect(
        FileNameFormatter.truncate('故宫初雪'),
        '故宫初雪',
      );
      expect(
        FileNameFormatter.truncate('今天天气真好呀'),
        '今天天气真好呀',
      );
    });

    test('刚好 10 个中文字符不截断', () {
      const tenChinese = '一二三四五六七八九十';
      expect(
        FileNameFormatter.truncate(tenChinese),
        tenChinese,
      );
    });

    test('超过 10 个中文字符在第 10 个汉字处截断并加省略号', () {
      expect(
        FileNameFormatter.truncate('今天去吃火锅特别开心真的绝了'),
        '今天去吃火锅特别开心...',
      );
    });

    test('纯英文与半角字符按 20 个字符预算截断', () {
      // 10 汉字权重 = 20 个 ASCII 字符
      expect(
        FileNameFormatter.truncate('Hello World Flutter!'), // 20 chars
        'Hello World Flutter!',
      );
      expect(
        FileNameFormatter.truncate('Hello World Flutter Extra!'),
        'Hello World Flutter...',
      );
    });

    test('中英文混合按权重准确截断', () {
      // 'Flutter' (7*0.5=3.5) + '体验报告' (4*1=4.0) = 7.5 <= 10.0
      expect(
        FileNameFormatter.truncate('Flutter体验报告'),
        'Flutter体验报告',
      );
      // 'Flutter' (3.5) + '开发实战指南非常棒' (9*1=9.0) = 12.5 > 10.0
      // 3.5 + 6.0 (6个汉字: '开发实战指南') = 9.5 <= 10.0
      expect(
        FileNameFormatter.truncate('Flutter开发实战指南非常棒'),
        'Flutter开发实战指南...',
      );
    });
  });

  group('FileNameFormatter.buildBaseName', () {
    test('正常标题生成清洗后截断的名称', () {
      expect(
        FileNameFormatter.buildBaseName('【美食推荐】带大家打卡北京超赞的胡同涮肉'),
        '【美食推荐】带大家打...',
      );
    });

    test('空标题/纯空白/纯非法字符回退到 YuYin_timestamp', () {
      expect(
        FileNameFormatter.buildBaseName('', fallbackTimestamp: 123456),
        'YuYin_123456',
      );
      expect(
        FileNameFormatter.buildBaseName('   ', fallbackTimestamp: 123456),
        'YuYin_123456',
      );
      expect(
        FileNameFormatter.buildBaseName('///???:::***', fallbackTimestamp: 123456),
        'YuYin_123456',
      );
      expect(
        FileNameFormatter.buildBaseName(null, fallbackTimestamp: 123456),
        'YuYin_123456',
      );
    });
  });

  group('FileNameFormatter.formatFileName 资源后缀与单/多资源规则', () {
    const videoItem = MediaItem(url: 'https://v.mp4', type: MediaType.video);
    const imageItem1 = MediaItem(url: 'https://a.jpg', type: MediaType.image);
    const imageItem2 = MediaItem(url: 'https://b.jpg', type: MediaType.image);
    const imageItem3 = MediaItem(url: 'https://c.png', type: MediaType.image);
    const audioItem = MediaItem(url: 'https://m.mp3', type: MediaType.audio);

    test('单个视频下载：同类资源只有 1 个，不加序号后缀', () {
      final all = [videoItem];
      final name = FileNameFormatter.formatFileName(
        item: videoItem,
        allItems: all,
        currentIndex: 0,
        rawTitleOrDesc: '今天天气真好呀',
      );
      expect(name, '今天天气真好呀.mp4');
    });

    test('多个同类资源（多图）：同类资源数量大于 1，必须加 _1, _2, _3 序号后缀', () {
      final all = [imageItem1, imageItem2, imageItem3];

      final name1 = FileNameFormatter.formatFileName(
        item: imageItem1,
        allItems: all,
        currentIndex: 0,
        rawTitleOrDesc: '今天去吃火锅特别开心真的绝了',
      );
      final name2 = FileNameFormatter.formatFileName(
        item: imageItem2,
        allItems: all,
        currentIndex: 1,
        rawTitleOrDesc: '今天去吃火锅特别开心真的绝了',
      );
      final name3 = FileNameFormatter.formatFileName(
        item: imageItem3,
        allItems: all,
        currentIndex: 2,
        rawTitleOrDesc: '今天去吃火锅特别开心真的绝了',
      );

      expect(name1, '今天去吃火锅特别开心..._1.jpg');
      expect(name2, '今天去吃火锅特别开心..._2.jpg');
      expect(name3, '今天去吃火锅特别开心..._3.png');
    });

    test('单个多种资源（例如实况图：1 图 + 1 视频 + 1 音频）：同类均为 1，严格不加序号后缀', () {
      final all = [imageItem1, videoItem, audioItem];

      final imgName = FileNameFormatter.formatFileName(
        item: imageItem1,
        allItems: all,
        currentIndex: 0,
        rawTitleOrDesc: '故宫初雪留念',
      );
      final vidName = FileNameFormatter.formatFileName(
        item: videoItem,
        allItems: all,
        currentIndex: 1,
        rawTitleOrDesc: '故宫初雪留念',
      );
      final audName = FileNameFormatter.formatFileName(
        item: audioItem,
        allItems: all,
        currentIndex: 2,
        rawTitleOrDesc: '故宫初雪留念',
      );

      expect(imgName, '故宫初雪留念.jpg');
      expect(vidName, '故宫初雪留念.mp4');
      expect(audName, '故宫初雪留念.mp3');
    });

    test('图文配乐（1 图 + 1 音频）：自适应推断 m4a，且两者均不加序号后缀', () {
      const bgmAudio = MediaItem(
        url: 'https://sf1-cdn-tos.douyinstatic.com/obj/tos-cn-ve-2774/music',
        type: MediaType.audio,
      );
      final all = [imageItem1, bgmAudio];

      final imgName = FileNameFormatter.formatFileName(
        item: imageItem1,
        allItems: all,
        currentIndex: 0,
        rawTitleOrDesc: 'donk就是会刷数据的niko# niko',
      );
      final audName = FileNameFormatter.formatFileName(
        item: bgmAudio,
        allItems: all,
        currentIndex: 1,
        rawTitleOrDesc: 'donk就是会刷数据的niko# niko',
      );

      expect(imgName, 'donk就是会刷数据的ni....jpg');
      expect(audName, 'donk就是会刷数据的ni....m4a');
    });

    test('多个多种资源（例如 2 套实况图：2 图 + 2 视频）：图片与视频各自按同类序号 _1, _2 编号', () {
      const liveVideo1 = MediaItem(url: 'https://v1.mp4', type: MediaType.video);
      const liveVideo2 = MediaItem(url: 'https://v2.mp4', type: MediaType.video);
      final all = [imageItem1, liveVideo1, imageItem2, liveVideo2];

      final img1 = FileNameFormatter.formatFileName(
        item: imageItem1,
        allItems: all,
        currentIndex: 0,
        rawTitleOrDesc: '胡同漫步记录',
      );
      final vid1 = FileNameFormatter.formatFileName(
        item: liveVideo1,
        allItems: all,
        currentIndex: 1,
        rawTitleOrDesc: '胡同漫步记录',
      );
      final img2 = FileNameFormatter.formatFileName(
        item: imageItem2,
        allItems: all,
        currentIndex: 2,
        rawTitleOrDesc: '胡同漫步记录',
      );
      final vid2 = FileNameFormatter.formatFileName(
        item: liveVideo2,
        allItems: all,
        currentIndex: 3,
        rawTitleOrDesc: '胡同漫步记录',
      );

      expect(img1, '胡同漫步记录_1.jpg');
      expect(vid1, '胡同漫步记录_1.mp4');
      expect(img2, '胡同漫步记录_2.jpg');
      expect(vid2, '胡同漫步记录_2.mp4');
    });
  });
}
