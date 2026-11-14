import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/common/batch_video_quality.dart';
import '../../models/save_page/selection/aggregate_state.dart';
import '../../models/save_page/selection/quality_indicator.dart';
import '../../models/save_page/selection/terminal_seed.dart';
import '../../models/save_page/selection/terminal_view.dart';

/// 保存页唯一记忆模板：只记录 Terminal 的 5 个值
///
/// - picture / live / music / video：只接受 all / none
/// - quality：只接受 highest / lowest
/// - NotAll / Empty / mixed / none 只是运行时聚合，不写入模板
class TerminalMemoryStore {
  TerminalMemoryStore._();

  static const String _fileName = 'terminal_memory.json';

  static AggregateState _picture = AggregateState.all;
  static AggregateState _live = AggregateState.all;
  static AggregateState _music = AggregateState.all;
  static AggregateState _video = AggregateState.all;
  static BatchVideoQualityMode _quality = BatchVideoQualityMode.highest;

  static TerminalSeed get seed => TerminalSeed(
        picture: _picture,
        live: _live,
        music: _music,
        video: _video,
        quality: _quality,
      );

  /// 会话结束：按 Terminal 最终聚合写回模板
  static Future<void> capture(TerminalSelectionView terminal) async {
    var changed = false;

    AggregateState apply(AggregateState next, AggregateState current) {
      if (next != AggregateState.all && next != AggregateState.none) {
        return current;
      }
      if (next != current) changed = true;
      return next;
    }

    final picture = apply(terminal.picture, _picture);
    final live = apply(terminal.live, _live);
    final music = apply(terminal.music, _music);
    final video = apply(terminal.videoSelection, _video);

    var quality = _quality;
    if (terminal.quality == QualityIndicator.highest) {
      if (_quality != BatchVideoQualityMode.highest) changed = true;
      quality = BatchVideoQualityMode.highest;
    } else if (terminal.quality == QualityIndicator.lowest) {
      if (_quality != BatchVideoQualityMode.lowest) changed = true;
      quality = BatchVideoQualityMode.lowest;
    }

    _picture = picture;
    _live = live;
    _music = music;
    _video = video;
    _quality = quality;

    if (changed) await _save();
  }

  static Future<void> init() async {
    try {
      final file = await _file();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      _picture = _readState(decoded['picture'], _picture);
      _live = _readState(decoded['live'], _live);
      _music = _readState(decoded['music'], _music);
      _video = _readState(decoded['video'], _video);
      _quality = decoded['quality'] == BatchVideoQualityMode.lowest.name
          ? BatchVideoQualityMode.lowest
          : BatchVideoQualityMode.highest;
    } catch (_) {
      // 读取失败沿用默认模板
    }
  }

  static AggregateState _readState(Object? raw, AggregateState fallback) {
    if (raw == AggregateState.all.name) return AggregateState.all;
    if (raw == AggregateState.none.name) return AggregateState.none;
    return fallback;
  }

  @visibleForTesting
  static void reset({
    AggregateState picture = AggregateState.all,
    AggregateState live = AggregateState.all,
    AggregateState music = AggregateState.all,
    AggregateState video = AggregateState.all,
    BatchVideoQualityMode quality = BatchVideoQualityMode.highest,
  }) {
    _picture = picture;
    _live = live;
    _music = music;
    _video = video;
    _quality = quality;
  }

  static Future<void> _save() async {
    try {
      final file = await _file();
      final data = <String, dynamic>{
        'picture': _picture.name,
        'live': _live.name,
        'music': _music.name,
        'video': _video.name,
        'quality': _quality.name,
      };
      await file.writeAsString(jsonEncode(data), flush: true);
    } catch (_) {
      // 写入失败不影响内存状态
    }
  }

  static Future<File> _file() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_fileName');
  }
}
