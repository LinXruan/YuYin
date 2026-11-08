import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/douyin_sniffer.dart';

void main() {
  group('parseChannelItems', () {
    test('非 List 返回空列表', () {
      expect(DouyinSniffer.parseChannelItems(null), isEmpty);
      expect(DouyinSniffer.parseChannelItems('bad'), isEmpty);
      expect(DouyinSniffer.parseChannelItems(<dynamic>[]), isEmpty);
    });

    test('跳过非 Map 与空 URL，保留视频/图片类型', () {
      final items = DouyinSniffer.parseChannelItems([
        {
          'url': 'https://a.mp4',
          'mediaType': 'video',
          'resolution': '1080x1920',
        },
        {'url': '', 'mediaType': 'image'},
        'bad',
        {'url': 'https://b.jpg', 'mediaType': 'image'},
      ]);

      expect(items, hasLength(2));
      expect(items[0].type, MediaType.video);
      expect(items[0].resolution, '1080x1920');
      expect(items[1].type, MediaType.image);
      expect(items[1].url, 'https://b.jpg');
    });
  });

  group('webViewFallbackTimeoutFor', () {
    test('时间充足时使用 12 秒默认值', () {
      expect(
        DouyinSniffer.webViewFallbackTimeoutFor(Duration.zero),
        const Duration(seconds: 12),
      );
    });

    test('剩余 10 秒时压缩到 8 秒', () {
      expect(
        DouyinSniffer.webViewFallbackTimeoutFor(const Duration(seconds: 20)),
        const Duration(seconds: 8),
      );
    });

    test('剩余 7 秒时保底 5 秒', () {
      expect(
        DouyinSniffer.webViewFallbackTimeoutFor(const Duration(seconds: 23)),
        const Duration(seconds: 5),
      );
    });

    test('剩余不足 6 秒时跳过 C 兜底', () {
      expect(
        DouyinSniffer.webViewFallbackTimeoutFor(const Duration(seconds: 24)),
        isNull,
      );
      expect(
        DouyinSniffer.webViewFallbackTimeoutFor(const Duration(seconds: 30)),
        isNull,
      );
    });
  });

  group('shareFallbackErrorMessage', () {
    test('深链中断使用专门提示', () {
      expect(
        DouyinSniffer.shareFallbackErrorMessage('net::ERR_UNKNOWN_URL_SCHEME'),
        '分享页被深链中断，请稍后重试',
      );
      expect(
        DouyinSniffer.shareFallbackErrorMessage('ERR_ABORTED'),
        '分享页被深链中断，请稍后重试',
      );
    });

    test('其它错误使用通用文案', () {
      expect(
        DouyinSniffer.shareFallbackErrorMessage(null),
        '分享页兜底未返回作品数据，请稍后重试',
      );
      expect(
        DouyinSniffer.shareFallbackErrorMessage('timeout'),
        '分享页兜底未返回作品数据，请稍后重试',
      );
    });
  });

  group('loginStateDetection', () {
    test('正确解析 Channel 回传的 login_state 消息', () {
      expect(
        DouyinSniffer.parseChannelLoginState({
          'type': 'login_state',
          'loggedIn': false,
          'reason': 'dom_login_button',
        }),
        isFalse,
      );

      expect(
        DouyinSniffer.parseChannelLoginState({
          'type': 'login_state',
          'loggedIn': true,
          'reason': 'probe_passport_valid',
        }),
        isTrue,
      );

      expect(DouyinSniffer.parseChannelLoginState({'type': 'result'}), isNull);
      expect(DouyinSniffer.parseChannelLoginState('bad'), isNull);
    });
  });
}
