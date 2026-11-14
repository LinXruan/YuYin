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