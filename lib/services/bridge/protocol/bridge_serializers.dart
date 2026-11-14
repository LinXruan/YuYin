part of '../server/agent_automation_server.dart';

/// 端点序列化：保存结果、媒体条目与画质模式。
extension AgentSerialization on AgentAutomationServer {
  /// 将画质字符串转换为批量保存模式
  BatchVideoQualityMode _qualityModeFrom(String? raw) {
    if (raw == 'lowest') return BatchVideoQualityMode.lowest;
    if (raw == 'mixed') return BatchVideoQualityMode.mixed;
    return BatchVideoQualityMode.highest;
  }

  Map<String, dynamic> _serializeWorkSaveResult(WorkSaveResult result) {
    return {
      'url': result.url,
      'success': result.success,
      'savedTypes': result.savedTypes.map((type) => type.name).toList(),
      'savedBaseName': result.savedBaseName,
      if (result.error != null) 'error': result.error,
    };
  }
  List<Map<String, dynamic>> _serializeItems(List<MediaItem> items) {
    return items.asMap().entries.map((entry) {
      final i = entry.key;
      final item = entry.value;
      return {
        'index': i,
        'type': item.type.name,
        'url': item.url,
        'resolution': item.resolution,
        'resolutionLabel': item.resolutionLabel,
        'dataSize': item.dataSize,
        'formattedSize': item.formattedSize,
        'bitRate': item.bitRate,
        'formattedBitRate': item.formattedBitRate,
        'gearName': item.gearName,
      };
    }).toList();
  }
}
