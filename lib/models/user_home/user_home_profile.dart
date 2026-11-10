/// 抖音用户主页作者基础信息（头像与昵称）
class UserHomeProfile {
  const UserHomeProfile({
    required this.secUid,
    required this.nickname,
    this.avatarUrl = '',
  });

  /// 用户的 sec_uid 唯一标识
  final String secUid;

  /// 作者昵称
  final String nickname;

  /// 作者头像直链（未获取时为空字符串）
  final String avatarUrl;

  /// 是否包含有效信息（至少有昵称或头像）
  bool get isValid => nickname.isNotEmpty || avatarUrl.isNotEmpty;

  Map<String, dynamic> toMap() => {
        'secUid': secUid,
        'nickname': nickname,
        'avatarUrl': avatarUrl,
      };

  factory UserHomeProfile.fromMap(Map<String, dynamic> map) {
    return UserHomeProfile(
      secUid: map['secUid']?.toString() ?? '',
      nickname: map['nickname']?.toString() ?? '',
      avatarUrl: map['avatarUrl']?.toString() ?? '',
    );
  }
}
