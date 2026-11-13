part of '../../../parse_page.dart';

/// parse progress flow
extension _ParseParseProgressFlowFlow on _ParsePageState {
  String _mediaSummaryFor(SingleWorkResult? parsed, WorkMediaKind kind) {
    if (parsed == null) {
      return kind == WorkMediaKind.image ? '图集/文案' : '视频/文案';
    }
    final tags = <String>[];
    if (parsed.videoCount > 0) {
      tags.add(parsed.isImagePost ? '实况' : '视频');
    }
    if (parsed.imageCount > 0) tags.add('图集');
    if (parsed.audioCount > 0) tags.add('音频');
    tags.add('文案');
    return tags.join('/');
  }

  /// 画质模式中文文案

  String _qualityLabel(BatchVideoQualityMode mode) {
    switch (mode) {
      case BatchVideoQualityMode.highest:
        return '最高画质';
      case BatchVideoQualityMode.lowest:
        return '最低画质';
      case BatchVideoQualityMode.mixed:
        return '混合画质';
    }
  }

  /// 根据作品类型弹出对应选择面板，返回用户选中的资源

  void _updateBatchSaveProgress(int current, int total, String message) {
    if (!mounted) return;
    final prefix = message.startsWith('正在准备') ? '正在准备' : '正在保存';
    widget.logs.upsertLast(prefix, message);
    final overall = total == 0 ? 0.0 : current / total;
    _downloadProgress.value = overall.clamp(0.0, 1.0).toDouble();
  }

  /// 刷新批量下载进度（仅驱动局部进度条更新，避免触发整体界面重绘）

  void _updateBatchProgress(int current, int total, double itemProgress) {
    final percent = (itemProgress * 100).round();
    final key = '$current/$total/$percent';
    if (!mounted || key == _lastProgressKey) return;
    _lastProgressKey = key;

    // 总进度 = 已完成项 + 当前项进度
    final overall = total == 0 ? 0.0 : ((current - 1) + itemProgress) / total;
    widget.logs.upsertLast('正在下载第', '正在下载第 $current/$total 个资源（$percent%）...');
    _downloadProgress.value = overall.clamp(0.0, 1.0).toDouble();
  }

  /// 把异常转换成简短的中文提示

  String _friendlyError(Object error) {
    if (error is ArticleWorkException) {
      return error.message;
    }
    if (error is TimeoutException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;
      return '捕获超时，请检查链接是否有效后重试';
    }
    if (error is DioException && error.response?.statusCode == 403) {
      return '视频服务器拒绝了请求（403），请稍后重试';
    }
    return error.toString().replaceFirst(
      RegExp(r'^(Exception|Bad state|FormatException): '),
      '',
    );
  }
}
