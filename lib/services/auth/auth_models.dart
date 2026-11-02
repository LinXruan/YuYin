import 'package:flutter/foundation.dart';

/// 认证会话状态机
enum AuthStatus {
  /// 确认为未登录状态
  unauthenticated,

  /// 已登录且会话经检验合法
  authenticated,

  /// 正在服务端发起权威校验
  verifying,

  /// 服务端明确告知会话已失效（如已被踢下线、Token 过期）
  expired,
}

/// 会话数据模型（不可变值对象）
@immutable
class AuthSession {
  const AuthSession({
    this.status = AuthStatus.unauthenticated,
    this.userId,
    this.lastVerifiedAt,
  });

  /// 未登录初始实例
  static const AuthSession unauthenticated = AuthSession(
    status: AuthStatus.unauthenticated,
  );

  final AuthStatus status;
  final String? userId;
  final DateTime? lastVerifiedAt;

  /// 是否具备可用登录态（authenticated 状态下有效）
  bool get isValid => status == AuthStatus.authenticated;

  /// 是否为需要展示登录引导的未就绪状态
  bool get needsLogin =>
      status == AuthStatus.unauthenticated || status == AuthStatus.expired;

  AuthSession copyWith({
    AuthStatus? status,
    String? userId,
    DateTime? lastVerifiedAt,
  }) {
    return AuthSession(
      status: status ?? this.status,
      userId: userId ?? this.userId,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AuthSession &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          userId == other.userId &&
          lastVerifiedAt == other.lastVerifiedAt;

  @override
  int get hashCode => Object.hash(status, userId, lastVerifiedAt);

  @override
  String toString() =>
      'AuthSession(status: $status, userId: $userId, lastVerifiedAt: $lastVerifiedAt)';
}

/// 远端权威鉴权结果类型
enum RemoteVerifyStatus {
  /// 凭证有效
  valid,

  /// 服务端明确返回未登录 / 凭证失效 (error_code 101 等)
  invalid,

  /// 网络离线、超时或限流（网络容灾，不判定为失效）
  networkError,
}

/// 远端权威核验结果
@immutable
class RemoteVerifyResult {
  const RemoteVerifyResult({
    required this.status,
    this.userId,
    this.message,
  });

  factory RemoteVerifyResult.valid({String? userId}) => RemoteVerifyResult(
        status: RemoteVerifyStatus.valid,
        userId: userId,
      );

  factory RemoteVerifyResult.invalid({String? message}) => RemoteVerifyResult(
        status: RemoteVerifyStatus.invalid,
        message: message,
      );

  factory RemoteVerifyResult.networkError({String? message}) =>
      RemoteVerifyResult(
        status: RemoteVerifyStatus.networkError,
        message: message,
      );

  final RemoteVerifyStatus status;
  final String? userId;
  final String? message;

  @override
  String toString() =>
      'RemoteVerifyResult(status: $status, userId: $userId, message: $message)';
}

