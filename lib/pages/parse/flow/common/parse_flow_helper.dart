import 'dart:async';

import 'package:dio/dio.dart';

import '../../../../models/common/batch_video_quality.dart';
import '../../../../models/save_page/work_kind.dart';
import '../../../../models/single_work/single_work_result.dart';
import '../../../../services/multi_work/article_work_exception.dart';

/// 解析流程辅助纯函数：错误翻译、媒体汇总文案、画质文案
class ParseFlowHelper {
  const ParseFlowHelper._();

  /// 媒体类型文案汇总
  static String mediaSummaryFor(SingleWorkResult? parsed, WorkMediaKind kind) {
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
  static String qualityLabel(BatchVideoQualityMode mode) {
    switch (mode) {
      case BatchVideoQualityMode.highest:
        return '最高画质';
      case BatchVideoQualityMode.lowest:
        return '最低画质';
      case BatchVideoQualityMode.mixed:
        return '混合画质';
    }
  }

  /// 把异常转换成简短的中文提示
  static String friendlyError(Object error) {
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
