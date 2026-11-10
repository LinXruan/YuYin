import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/services/single_work/i_single_work_extractor.dart';
import 'package:yuyin/services/single_work/single_work_extractor.dart';
import 'package:yuyin/services/user_home/i_user_home_extractor.dart';
import 'package:yuyin/services/user_home/user_home_extractor.dart';

class _FakeSingleWorkDelegate implements ISingleWorkSnifferDelegate {
  bool cancelled = false;
  String? lastShareUrl;

  @override
  Future<SingleWorkResult> sniffVideoUrl(String shareUrl) async {
    lastShareUrl = shareUrl;
    return const SingleWorkResult(
      items: [
        MediaItem(url: 'https://video.test/1.mp4', type: MediaType.video),
      ],
      cookie: 'test=1',
      isImagePost: false,
      title: '测试单作品',
    );
  }

  @override
  void cancelActiveTask() {
    cancelled = true;
  }
}

class _FakeUserHomeDelegate implements IUserHomeSnifferDelegate {
  bool cancelled = false;
  String? lastProfileUrl;
  String? lastHomeUrl;

  @override
  Future<UserHomeProfile> sniffUserProfile(String homeUrl) async {
    lastProfileUrl = homeUrl;
    return const UserHomeProfile(
      secUid: 'MS4wLjABAAAA_test',
      nickname: '测试作者',
      avatarUrl: 'https://p3.test/avatar.jpeg',
    );
  }

  @override
  Future<UserHomeResult> sniffUserHomeUrl(String homeUrl) async {
    lastHomeUrl = homeUrl;
    return const UserHomeResult(
      secUid: 'MS4wLjABAAAA_test',
      nickname: '测试作者',
      avatarUrl: 'https://p3.test/avatar.jpeg',
      tabCount: 10,
      workUrls: ['https://www.douyin.com/video/1'],
    );
  }

  @override
  void cancelActiveTask() {
    cancelled = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('PLAN_57: 架构重构与业务分层规范测试', () {
    test('1. 模型层解耦：SingleWorkResult 资源过滤与展示名称准确', () {
      const videoItem = MediaItem(
        url: 'https://video.example.com/1.mp4',
        type: MediaType.video,
        resolution: '1080x1920',
        gearName: '1080p',
      );
      const imageItem = MediaItem(
        url: 'https://image.example.com/1.jpeg',
        type: MediaType.image,
      );
      const audioItem = MediaItem(
        url: 'https://audio.example.com/1.mp3',
        type: MediaType.audio,
      );

      final result = SingleWorkResult(
        items: const [videoItem, imageItem, audioItem],
        cookie: 'test_cookie=123',
        isImagePost: false,
        title: '测试作品标题',
        desc: '作品详细描述文案',
        coverUrl: 'https://cover.example.com/thumb.jpeg',
      );

      expect(result.displayTitle, '测试作品标题');
      expect(result.coverUrl, 'https://cover.example.com/thumb.jpeg');
      expect(result.videoCount, 1);
      expect(result.imageCount, 1);
      expect(result.audioCount, 1);
      expect(result.videoItems.first.url, videoItem.url);
      expect(result.imageItems.first.url, imageItem.url);
      expect(result.audioItems.first.url, audioItem.url);

      // 验证向后兼容的 SniffResult 别名类型一致性
      final SniffResult aliasCheck = result;
      expect(aliasCheck.displayTitle, '测试作品标题');
    });

    test('2. 模型层解耦：UserHomeProfile 与 UserHomeResult 字段与映射完整', () {
      const profile = UserHomeProfile(
        secUid: 'MS4wLjABAAAA_test_uid',
        nickname: '余音测试作者',
        avatarUrl: 'https://p3-pc.douyinpic.com/aweme-avatar/tos-test.jpeg',
      );
      expect(profile.isValid, isTrue);
      expect(profile.nickname, '余音测试作者');
      expect(profile.avatarUrl, contains('aweme-avatar'));

      const result = UserHomeResult(
        secUid: 'MS4wLjABAAAA_test_uid',
        nickname: '余音测试作者',
        avatarUrl: 'https://p3-pc.douyinpic.com/aweme-avatar/tos-test.jpeg',
        tabCount: 42,
        workUrls: [
          'https://www.douyin.com/video/1001',
          'https://www.douyin.com/video/1002',
        ],
        workCovers: {
          'https://www.douyin.com/video/1001': 'https://cover.example.com/1.jpg',
          'https://www.douyin.com/video/1002': 'https://cover.example.com/2.jpg',
        },
        workTitles: {
          'https://www.douyin.com/video/1001': '作品标题1',
          'https://www.douyin.com/video/1002': '作品标题2',
        },
      );

      expect(result.worksTotalTag, 42);
      expect(result.count, 2);
      expect(result.coversCount, 2);
      expect(result.titlesCount, 2);
      expect(result.getCover('https://www.douyin.com/video/1001'),
          'https://cover.example.com/1.jpg');
      expect(result.getTitle('https://www.douyin.com/video/1002'), '作品标题2');
      expect(result.profile.nickname, profile.nickname);
      expect(result.profile.avatarUrl, profile.avatarUrl);
    });

    test('3. 契约规范：ISingleWorkExtractor 链接提取与委托调度', () async {
      final fakeDelegate = _FakeSingleWorkDelegate();
      final ISingleWorkExtractor extractor = SingleWorkExtractor(fakeDelegate);

      const validShareText =
          '7.12 04/06 l@u.cl ysm:/ 复制打开抖音看视频 https://v.douyin.com/iRoABCD/ 这是作品';
      const homeText =
          '来看作者主页 https://www.douyin.com/user/MS4wLjABAAAA123456?from_tab_name=main';

      final shareUrl = extractor.extractShareUrl(validShareText);
      expect(shareUrl, 'https://v.douyin.com/iRoABCD/');

      // 主页链接不应被当作单作品提取
      final nonShareUrl = extractor.extractShareUrl(homeText);
      expect(nonShareUrl, isNull);

      final result = await extractor.extract(shareUrl!);
      expect(result.displayTitle, '测试单作品');
      expect(fakeDelegate.lastShareUrl, shareUrl);

      extractor.cancel();
      expect(fakeDelegate.cancelled, isTrue);
    });

    test('4. 契约规范：IUserHomeExtractor 链接提取与委托调度', () async {
      final fakeDelegate = _FakeUserHomeDelegate();
      final IUserHomeExtractor extractor = UserHomeExtractor(fakeDelegate);

      const validHomeText =
          '作者主页 https://www.douyin.com/user/MS4wLjABAAAA123456?from_tab_name=main 点击关注';
      const shareText = 'https://v.douyin.com/iRoABCD/ 单作品';

      final homeUrl = extractor.extractHomeUrl(validHomeText);
      expect(homeUrl,
          'https://www.douyin.com/user/MS4wLjABAAAA123456?from_tab_name=main');

      // 单作品链接不应被当作主页提取
      final nonHomeUrl = extractor.extractHomeUrl(shareText);
      expect(nonHomeUrl, isNull);

      // 测试 extractProfile
      final profile = await extractor.extractProfile(homeUrl!);
      expect(profile.nickname, '测试作者');
      expect(fakeDelegate.lastProfileUrl, homeUrl);

      // 测试 extractAllWorks
      final works = await extractor.extractAllWorks(homeUrl);
      expect(works.count, 1);
      expect(works.worksTotalTag, 10);
      expect(fakeDelegate.lastHomeUrl, homeUrl);

      extractor.cancel();
      expect(fakeDelegate.cancelled, isTrue);
    });
  });
}
