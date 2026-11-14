/// 应用内更新下载状态模型
class AppUpdateStatus {
  const AppUpdateStatus({
    this.isDownloading = false,
    this.progress = 0.0,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.version,
    this.targetApkPath,
    this.errorMessage,
  });

  final bool isDownloading;
  final double progress; // 0.0 ~ 1.0
  final int receivedBytes;
  final int totalBytes;
  final String? version;
  final String? targetApkPath;
  final String? errorMessage;

  AppUpdateStatus copyWith({
    bool? isDownloading,
    double? progress,
    int? receivedBytes,
    int? totalBytes,
    String? version,
    String? targetApkPath,
    String? errorMessage,
  }) {
    return AppUpdateStatus(
      isDownloading: isDownloading ?? this.isDownloading,
      progress: progress ?? this.progress,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      version: version ?? this.version,
      targetApkPath: targetApkPath ?? this.targetApkPath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
