// 检查更新结果模型。
import 'update_release_info.dart';
/// 检查更新返回结果
class UpdateCheckResult {
  const UpdateCheckResult._({
    this.info,
    this.errorMessage,
    this.isCancelled = false,
  });

  const UpdateCheckResult.success(UpdateReleaseInfo info)
      : this._(info: info);

  const UpdateCheckResult.error(String message)
      : this._(errorMessage: message);

  const UpdateCheckResult.cancelled()
      : this._(isCancelled: true);

  final UpdateReleaseInfo? info;
  final String? errorMessage;
  final bool isCancelled;

  bool get isSuccess => info != null;
}
