import 'user_home_profile.dart';

/// 抖音用户主页作品批量捕获结果
class UserHomeResult {
  const UserHomeResult({
    required this.secUid,
    required this.nickname,
    this.avatarUrl = '',
    required this.workUrls,
    this.workCovers = const {},
    this.workTitles = const {},
    this.tabCount,
  });

  /// 用户的 sec_uid 唯一标识
  final String secUid;

  /// 作者昵称
  final String nickname;

  /// 作者头像直链（未获取时为空字符串）
  final String avatarUrl;

  /// 作者基础信息（头像与昵称）
  UserHomeProfile get profile => UserHomeProfile(
        secUid: secUid,
        nickname: nickname,
        avatarUrl: avatarUrl,
      );

  /// 捕获到的所有作品链接列表（去重且按页面顺序）
  final List<String> workUrls;

  /// 作品链接至封面图片直链的映射字典
  final Map<String, String> workCovers;

  /// 作品链接至作品名称/标题的映射字典
  final Map<String, String> workTitles;

  /// 页面 Tab 标注的作品总数（如无则为 null）
  final int? tabCount;

  /// 作品数量 Tag 标注总数（若为空则为 0）
  int get worksTotalTag => tabCount ?? 0;

  /// 捕获到的作品数量
  int get count => workUrls.length;

  /// 已成功关联封面的作品总数
  int get coversCount => workCovers.length;

  /// 已成功关联标题/名称的作品总数
  int get titlesCount => workTitles.length;

  /// 获取指定作品的封面直链
  String? getCover(String workUrl) => workCovers[workUrl];

  /// 获取指定作品的名称/标题
  String? getTitle(String workUrl) => workTitles[workUrl];

  /// 按作品列表顺序输出对应的封面图列表（未捕获的为空字符串）
  List<String> get coverList =>
      workUrls.map((u) => workCovers[u] ?? '').toList();

  /// 按作品列表顺序输出对应的标题列表（未捕获的为空字符串）
  List<String> get titleList =>
      workUrls.map((u) => workTitles[u] ?? '').toList();

  Map<String, dynamic> toMap() => {
        'secUid': secUid,
        'nickname': nickname,
        'avatarUrl': avatarUrl,
        'count': count,
        'tabCount': tabCount,
        'worksTotalTag': worksTotalTag,
        'workUrls': workUrls,
        'workCovers': workCovers,
        'coversCount': coversCount,
        'workTitles': workTitles,
        'titlesCount': titlesCount,
      };
}
