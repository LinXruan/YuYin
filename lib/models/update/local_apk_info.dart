import 'dart:io';

/// 本地已扫描到的安装包信息
class LocalApkInfo {
  const LocalApkInfo({
    required this.file,
    required this.version,
    required this.fileName,
  });

  final File file;
  final String version;
  final String fileName;
}
