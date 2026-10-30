/// 嗅探结果：无水印直链、WebView Cookie 与分辨率
class SniffResult {
  const SniffResult({
    required this.videoUrl,
    required this.cookie,
    required this.width,
    required this.height,
  });

  final String videoUrl;
  final String cookie;
  final int width;
  final int height;

  /// 常见画质标签（竖屏按短边计算），未知分辨率返回空字符串
  String get resolutionLabel {
    if (width <= 0 || height <= 0) return '';
    final shortSide = width < height ? width : height;
    if (shortSide >= 2160) return '4K';
    if (shortSide >= 1080) return '1080P';
    if (shortSide >= 720) return '720P';
    return shortSide >= 540 ? '540P' : '${width}x$height';
  }
}
