import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../models/media_item.dart';

/// 存储位置配置模型（单作品三项 + 主页三项）
class SaveLocationConfig {
  const SaveLocationConfig({
    this.videoUri,
    this.videoDisplayPath = defaultVideoDir,
    this.imageUri,
    this.imageDisplayPath = defaultImageDir,
    this.audioUri,
    this.audioDisplayPath = defaultAudioDir,
    this.homeVideoUri,
    this.homeVideoDisplayPath = defaultHomeBaseDir,
    this.homeImageUri,
    this.homeImageDisplayPath = defaultHomeBaseDir,
    this.homeAudioUri,
    this.homeAudioDisplayPath = defaultHomeBaseDir,
  });

  static const String defaultVideoDir = '/Movies/YuYin/';
  static const String defaultImageDir = '/Pictures/YuYin/';
  static const String defaultAudioDir = '/Music/YuYin/';

  /// 主页链接默认基目录（运行时追加 作者/分类）
  static const String defaultHomeBaseDir = '/Download/YuYin/';

  // 单作品
  final String? videoUri;
  final String videoDisplayPath;
  final String? imageUri;
  final String imageDisplayPath;
  final String? audioUri;
  final String audioDisplayPath;

  // 主页链接
  final String? homeVideoUri;
  final String homeVideoDisplayPath;
  final String? homeImageUri;
  final String homeImageDisplayPath;
  final String? homeAudioUri;
  final String homeAudioDisplayPath;

  bool get isAllDefault =>
      videoUri == null &&
      imageUri == null &&
      audioUri == null &&
      homeVideoUri == null &&
      homeImageUri == null &&
      homeAudioUri == null &&
      videoDisplayPath == defaultVideoDir &&
      imageDisplayPath == defaultImageDir &&
      audioDisplayPath == defaultAudioDir &&
      homeVideoDisplayPath == defaultHomeBaseDir &&
      homeImageDisplayPath == defaultHomeBaseDir &&
      homeAudioDisplayPath == defaultHomeBaseDir;

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

  String getHomeDisplayPath(MediaType type) {
    switch (type) {
      case MediaType.video:
        return homeVideoDisplayPath;
      case MediaType.image:
        return homeImageDisplayPath;
      case MediaType.audio:
        return homeAudioDisplayPath;
    }
  }

  String? getHomeTreeUri(MediaType type) {
    switch (type) {
      case MediaType.video:
        return homeVideoUri;
      case MediaType.image:
        return homeImageUri;
      case MediaType.audio:
        return homeAudioUri;
    }
  }

  String getDisplayPathFor(SaveLocationTarget target) =>
      target.isHome ? getHomeDisplayPath(target.mediaType) : getDisplayPath(target.mediaType);

  String? getTreeUriFor(SaveLocationTarget target) =>
      target.isHome ? getHomeTreeUri(target.mediaType) : getTreeUri(target.mediaType);

  SaveLocationConfig copyWith({
    String? Function()? videoUri,
    String? videoDisplayPath,
    String? Function()? imageUri,
    String? imageDisplayPath,
    String? Function()? audioUri,
    String? audioDisplayPath,
    String? Function()? homeVideoUri,
    String? homeVideoDisplayPath,
    String? Function()? homeImageUri,
    String? homeImageDisplayPath,
    String? Function()? homeAudioUri,
    String? homeAudioDisplayPath,
  }) {
    return SaveLocationConfig(
      videoUri: videoUri != null ? videoUri() : this.videoUri,
      videoDisplayPath: videoDisplayPath ?? this.videoDisplayPath,
      imageUri: imageUri != null ? imageUri() : this.imageUri,
      imageDisplayPath: imageDisplayPath ?? this.imageDisplayPath,
      audioUri: audioUri != null ? audioUri() : this.audioUri,
      audioDisplayPath: audioDisplayPath ?? this.audioDisplayPath,
      homeVideoUri: homeVideoUri != null ? homeVideoUri() : this.homeVideoUri,
      homeVideoDisplayPath:
          homeVideoDisplayPath ?? this.homeVideoDisplayPath,
      homeImageUri: homeImageUri != null ? homeImageUri() : this.homeImageUri,
      homeImageDisplayPath:
          homeImageDisplayPath ?? this.homeImageDisplayPath,
      homeAudioUri: homeAudioUri != null ? homeAudioUri() : this.homeAudioUri,
      homeAudioDisplayPath:
          homeAudioDisplayPath ?? this.homeAudioDisplayPath,
    );
  }

  Map<String, dynamic> toJson() => {
        if (videoUri != null) 'videoUri': videoUri,
        'videoDisplayPath': videoDisplayPath,
        if (imageUri != null) 'imageUri': imageUri,
        'imageDisplayPath': imageDisplayPath,
        if (audioUri != null) 'audioUri': audioUri,
        'audioDisplayPath': audioDisplayPath,
        if (homeVideoUri != null) 'homeVideoUri': homeVideoUri,
        'homeVideoDisplayPath': homeVideoDisplayPath,
        if (homeImageUri != null) 'homeImageUri': homeImageUri,
        'homeImageDisplayPath': homeImageDisplayPath,
        if (homeAudioUri != null) 'homeAudioUri': homeAudioUri,
        'homeAudioDisplayPath': homeAudioDisplayPath,
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
      homeVideoUri: json['homeVideoUri']?.toString(),
      homeVideoDisplayPath:
          json['homeVideoDisplayPath']?.toString() ?? defaultHomeBaseDir,
      homeImageUri: json['homeImageUri']?.toString(),
      homeImageDisplayPath:
          json['homeImageDisplayPath']?.toString() ?? defaultHomeBaseDir,
      homeAudioUri: json['homeAudioUri']?.toString(),
      homeAudioDisplayPath:
          json['homeAudioDisplayPath']?.toString() ?? defaultHomeBaseDir,
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
          audioDisplayPath == other.audioDisplayPath &&
          homeVideoUri == other.homeVideoUri &&
          homeVideoDisplayPath == other.homeVideoDisplayPath &&
          homeImageUri == other.homeImageUri &&
          homeImageDisplayPath == other.homeImageDisplayPath &&
          homeAudioUri == other.homeAudioUri &&
          homeAudioDisplayPath == other.homeAudioDisplayPath;

  @override
  int get hashCode => Object.hashAll([
        videoUri,
        videoDisplayPath,
        imageUri,
        imageDisplayPath,
        audioUri,
        audioDisplayPath,
        homeVideoUri,
        homeVideoDisplayPath,
        homeImageUri,
        homeImageDisplayPath,
        homeAudioUri,
        homeAudioDisplayPath,
      ]);
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

  /// 获取指定类型的当前展示路径（单作品）
  static String getDisplayPath(MediaType type) =>
      notifier.value.getDisplayPath(type);

  /// 获取指定类型的自定义 SAF 授权 Uri（单作品默认时为 null）
  static String? getTreeUri(MediaType type) => notifier.value.getTreeUri(type);

  /// 获取主页链接的展示基路径
  static String getHomeDisplayPath(MediaType type) =>
      notifier.value.getHomeDisplayPath(type);

  /// 获取主页链接的自定义 SAF 授权 Uri（默认时为 null）
  static String? getHomeTreeUri(MediaType type) =>
      notifier.value.getHomeTreeUri(type);

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

  /// 更新单个分类的保存位置（单作品）
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

  /// 更新主页链接中某一类型的基目录
  static Future<void> updateHomeLocation(
    MediaType type, {
    String? uri,
    required String displayPath,
  }) async {
    final cur = notifier.value;
    final updated = switch (type) {
      MediaType.video => cur.copyWith(
          homeVideoUri: () => uri,
          homeVideoDisplayPath: displayPath,
        ),
      MediaType.image => cur.copyWith(
          homeImageUri: () => uri,
          homeImageDisplayPath: displayPath,
        ),
      MediaType.audio => cur.copyWith(
          homeAudioUri: () => uri,
          homeAudioDisplayPath: displayPath,
        ),
    };

    notifier.value = updated;
    await _save(updated);
  }

  /// 一键重置回系统默认目录
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
