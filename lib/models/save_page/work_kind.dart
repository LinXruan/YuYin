/// 中层保存页中的作品类型
enum WorkMediaKind {
  /// 普通视频作品
  video,

  /// 图文 / 实况图集作品
  image,

  /// 纯文章作品（仅用于识别过滤，不进入保存页）
  article,
}

extension WorkMediaKindX on WorkMediaKind {
  /// 分类按钮与日志展示文案
  String get label {
    switch (this) {
      case WorkMediaKind.video:
        return '视频';
      case WorkMediaKind.image:
        return '图文';
      case WorkMediaKind.article:
        return '文章';
    }
  }

  /// 是否为可进入保存页的作品类型
  bool get isSaveable =>
      this == WorkMediaKind.video || this == WorkMediaKind.image;
}
