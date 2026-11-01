import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';

/// 存储位置配置模型
class SaveLocationConfig {
  const SaveLocationConfig({
    this.videoUri,
    this.videoDisplayPath = defaultVideoDir,
    this.imageUri,
    this.imageDisplayPath = defaultImageDir,
    this.audioUri,
    this.audioDisplayPath = defaultAudioDir,
  });

  static const String defaultVideoDir = '/Movies/YuYin/';
  static const String defaultImageDir = '/Pictures/YuYin/';
  static const String defaultAudioDir = '/Music/YuYin/';

  final String? videoUri;
  final String videoDisplayPath;
  final String? imageUri;
  final String imageDisplayPath;
  final String? audioUri;
  final String audioDisplayPath;

  bool get isAllDefault =>
      videoUri == null &&
      imageUri == null &&
      audioUri == null &&
      videoDisplayPath == defaultVideoDir &&
      imageDisplayPath == defaultImageDir &&
      audioDisplayPath == defaultAudioDir;

  String getDisplayPath(MediaType type) {
    switch (type) {
      case MediaType.video:
        return videoDisplayPath;
      case MediaType.image:
        return imageDisplayPath;
      case MediaType.audio:
        return audioDisplayPath;
    }
  }

  String? getTreeUri(MediaType type) {
    switch (type) {
      case MediaType.video:
        return videoUri;
      case MediaType.image:
        return imageUri;
      case MediaType.audio:
        return audioUri;
    }
  }

  SaveLocationConfig copyWith({
    String? Function()? videoUri,
    String? videoDisplayPath,
    String? Function()? imageUri,
    String? imageDisplayPath,
    String? Function()? audioUri,
    String? audioDisplayPath,
  }) {
    return SaveLocationConfig(
      videoUri: videoUri != null ? videoUri() : this.videoUri,
      videoDisplayPath: videoDisplayPath ?? this.videoDisplayPath,
      imageUri: imageUri != null ? imageUri() : this.imageUri,
      imageDisplayPath: imageDisplayPath ?? this.imageDisplayPath,
      audioUri: audioUri != null ? audioUri() : this.audioUri,
      audioDisplayPath: audioDisplayPath ?? this.audioDisplayPath,
    );
  }

  Map<String, dynamic> toJson() => {
        if (videoUri != null) 'videoUri': videoUri,
        'videoDisplayPath': videoDisplayPath,
        if (imageUri != null) 'imageUri': imageUri,
        'imageDisplayPath': imageDisplayPath,
        if (audioUri != null) 'audioUri': audioUri,
        'audioDisplayPath': audioDisplayPath,
      };

  factory SaveLocationConfig.fromJson(Map<String, dynamic> json) {
    return SaveLocationConfig(
      videoUri: json['videoUri']?.toString(),
      videoDisplayPath:
          json['videoDisplayPath']?.toString() ?? defaultVideoDir,
      imageUri: json['imageUri']?.toString(),
      imageDisplayPath:
          json['imageDisplayPath']?.toString() ?? defaultImageDir,
      audioUri: json['audioUri']?.toString(),
      audioDisplayPath:
          json['audioDisplayPath']?.toString() ?? defaultAudioDir,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SaveLocationConfig &&
          runtimeType == other.runtimeType &&
          videoUri == other.videoUri &&
          videoDisplayPath == other.videoDisplayPath &&
          imageUri == other.imageUri &&
          imageDisplayPath == other.imageDisplayPath &&
          audioUri == other.audioUri &&
          audioDisplayPath == other.audioDisplayPath;

  @override
  int get hashCode => Object.hash(
        videoUri,
        videoDisplayPath,
        imageUri,
        imageDisplayPath,
        audioUri,
        audioDisplayPath,
      );
}

/// 保存位置持久化存储中心
class SaveLocationStore {
  SaveLocationStore._();

  static const String _fileName = 'save_locations.json';

  /// 全局通知源，供 UI 与日志实时感知目录变更
  static final ValueNotifier<SaveLocationConfig> notifier =
      ValueNotifier(const SaveLocationConfig());

  /// 当前配置
  static SaveLocationConfig get current => notifier.value;

  /// 获取指定类型的当前展示路径
  static String getDisplayPath(MediaType type) =>
      notifier.value.getDisplayPath(type);

  /// 获取指定类型的自定义 SAF 授权 Uri（默认时为 null）
  static String? getTreeUri(MediaType type) => notifier.value.getTreeUri(type);

  /// 是否全部为默认路径
  static bool get isAllDefault => notifier.value.isAllDefault;

  /// 启动时读取本地配置
  static Future<void> init() async {
    try {
      final file = await _getFile();
      if (!await file.exists()) {
        notifier.value = const SaveLocationConfig();
        return;
      }
      final raw = await file.readAsString();
      final map = jsonDecode(raw);
      if (map is Map<String, dynamic>) {
        notifier.value = SaveLocationConfig.fromJson(map);
      }
    } catch (_) {
      notifier.value = const SaveLocationConfig();
    }
  }

  /// 更新单个分类的保存位置
  static Future<void> updateLocation(
    MediaType type, {
    String? uri,
    required String displayPath,
  }) async {
    final cur = notifier.value;
    final updated = switch (type) {
      MediaType.video => cur.copyWith(
          videoUri: () => uri,
          videoDisplayPath: displayPath,
        ),
      MediaType.image => cur.copyWith(
          imageUri: () => uri,
          imageDisplayPath: displayPath,
        ),
      MediaType.audio => cur.copyWith(
          audioUri: () => uri,
          audioDisplayPath: displayPath,
        ),
    };

    notifier.value = updated;
    await _save(updated);
  }

  /// 一键重置回系统默认三大分类目录
  static Future<void> resetToDefault() async {
    notifier.value = const SaveLocationConfig();
    try {
      final file = await _getFile();
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {}
  }

  static Future<File> _getFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}$_fileName');
  }

  static Future<void> _save(SaveLocationConfig config) async {
    try {
      final file = await _getFile();
      await file.writeAsString(jsonEncode(config.toJson()), flush: true);
    } catch (_) {}
  }
}

