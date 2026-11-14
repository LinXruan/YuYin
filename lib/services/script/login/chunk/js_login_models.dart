/// 登录事件类型
enum LoginEventType {
  loginSuccess,
  logoutEvent,
}

/// 登录状态简要模型（不保存任何用户昵称、个人隐私或敏感数据）
class LoginProfile {
  const LoginProfile({
    this.userId,
    this.source = 'unknown',
  });

  final String? userId;
  final String source;

  factory LoginProfile.fromJson(Map<String, dynamic> json) {
    return LoginProfile(
      userId: json['userId']?.toString() ?? json['user_id']?.toString(),
      source: json['source']?.toString() ?? 'unknown',
    );
  }

  Map<String, dynamic> toJson() => {
        if (userId != null) 'userId': userId,
        'source': source,
      };

  @override
  String toString() => 'LoginProfile(userId: $userId, source: $source)';
}

/// 登录通道消息事件
class LoginChannelEvent {
  const LoginChannelEvent({
    required this.type,
    this.profile,
  });

  final LoginEventType type;
  final LoginProfile? profile;
}