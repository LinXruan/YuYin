// 版本发布信息模型。
/// Release 更新信息模型
class UpdateReleaseInfo {
  const UpdateReleaseInfo({
    required this.version,
    required this.htmlUrl,
    required this.releaseNotes,
    required this.publishedAt,
    required this.hasUpdate,
    this.v8aDownloadUrl,
    this.universalDownloadUrl,
  });

  /// 最新发布的版本号（例如 1.2.4）
  final String version;

  /// GitHub Release 页面外部链接
  final String htmlUrl;

  /// 提取并格式化后的更新日志说明
  final String releaseNotes;

  /// 发布时间字符串
  final String publishedAt;

  /// 是否有新版本可用（最新版本 > 当前运行版本）
  final bool hasUpdate;

  /// v8a 轻量架构安装包直链 (若有)
  final String? v8aDownloadUrl;

  /// Universal 全架构通用安装包直链 (若有)
  final String? universalDownloadUrl;

  /// 获取指定架构的首选下载链接
  /// - [preferArm64] 为 true 时，仅匹配 v8a 架构包；
  /// - [preferArm64] 为 false 时，仅匹配 Universal 全架构通用包。
  String getDownloadUrl({bool preferArm64 = true}) {
    if (preferArm64) {
      if (v8aDownloadUrl != null && v8aDownloadUrl!.isNotEmpty) {
        return v8aDownloadUrl!;
      }
      return 'https://github.com/LinXruan/YuYin/releases/download/$version/YuYin_${version}_v8a.apk';
    } else {
      if (universalDownloadUrl != null && universalDownloadUrl!.isNotEmpty) {
        return universalDownloadUrl!;
      }
      return 'https://github.com/LinXruan/YuYin/releases/download/$version/YuYin_${version}_Universal.apk';
    }
  }
}
