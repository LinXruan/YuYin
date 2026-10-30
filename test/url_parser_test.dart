import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/utils/url_parser.dart';

void main() {
  group('UrlParser.extractDouyinUrl', () {
    test('从完整分享口令中提取 v.douyin.com 短链', () {
      const text = '7.45 复制打开抖音，看看【xxx的作品】https://v.douyin.com/iYxxxx/ 03/22';
      expect(
        UrlParser.extractDouyinUrl(text),
        'https://v.douyin.com/iYxxxx/',
      );
    });

    test('剥离链接末尾粘连的英文标点', () {
      const text = '链接：https://v.douyin.com/iYxxxx/., 快来看';
      expect(
        UrlParser.extractDouyinUrl(text),
        'https://v.douyin.com/iYxxxx/',
      );
    });

    test('链接后紧跟中文标点也能正确截断', () {
      const text = 'https://v.douyin.com/iYxxxx/，复制此链接';
      expect(
        UrlParser.extractDouyinUrl(text),
        'https://v.douyin.com/iYxxxx/',
      );
    });

    test('支持 www.douyin.com 长链接', () {
      const text =
          '看看这个 https://www.douyin.com/video/7300000000000000000?previous_page=app_code_link 精彩视频';
      expect(
        UrlParser.extractDouyinUrl(text),
        'https://www.douyin.com/video/7300000000000000000?previous_page=app_code_link',
      );
    });

    test('跳过非抖音链接，返回第一个抖音链接', () {
      const text =
          'https://www.example.com/a 和 https://v.douyin.com/abc123/ 都在这里';
      expect(
        UrlParser.extractDouyinUrl(text),
        'https://v.douyin.com/abc123/',
      );
    });

    test('没有链接时返回 null', () {
      expect(UrlParser.extractDouyinUrl('只有一段普通文字，没有链接'), isNull);
    });

    test('只有非抖音链接时返回 null', () {
      expect(
        UrlParser.extractDouyinUrl('https://www.example.com/video/123'),
        isNull,
      );
    });
  });

  group('UrlParser.extractAwemeId', () {
    test('从 /video/ 长链提取作品 ID', () {
      expect(
        UrlParser.extractAwemeId(
          'https://www.douyin.com/video/7693396647648409855'
          '?previous_page=app_code_link',
        ),
        '7693396647648409855',
      );
    });

    test('从 /note/ 链接提取作品 ID', () {
      expect(
        UrlParser.extractAwemeId(
          'https://www.douyin.com/note/7300000000000000000',
        ),
        '7300000000000000000',
      );
    });

    test('从 /slides/ 链接提取作品 ID', () {
      expect(
        UrlParser.extractAwemeId(
          'https://www.douyin.com/slides/7300000000000000000',
        ),
        '7300000000000000000',
      );
    });

    test('从 modal_id 查询参数提取作品 ID', () {
      expect(
        UrlParser.extractAwemeId(
          'https://www.douyin.com/discover?modal_id=7300000000000000000',
        ),
        '7300000000000000000',
      );
    });

    test('iesdouyin 分享页也能提取作品 ID', () {
      expect(
        UrlParser.extractAwemeId(
          'https://www.iesdouyin.com/share/video/7300000000000000000/',
        ),
        '7300000000000000000',
      );
    });

    test('短链没有作品 ID 时返回 null', () {
      expect(UrlParser.extractAwemeId('https://v.douyin.com/iYxxxx/'), isNull);
    });

    test('非抖音链接返回 null', () {
      expect(
        UrlParser.extractAwemeId(
          'https://www.youtube.com/video/7300000000000000000',
        ),
        isNull,
      );
    });

    test('ID 长度不在 10~25 位时返回 null', () {
      expect(
        UrlParser.extractAwemeId('https://www.douyin.com/video/12345'),
        isNull,
      );
    });
  });
}
