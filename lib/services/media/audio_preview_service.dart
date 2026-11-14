import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 音频试听播放状态
enum AudioPreviewState {
  idle,
  buffering,
  playing,
  paused,
  completed,
  error,
}

/// 基于原生平台通道的轻量级音频试听服务
class AudioPreviewService {
  AudioPreviewService({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('com.debug.yuyin/audio_player') {
    _channel.setMethodCallHandler(_handleNativeCall);
  }

  final MethodChannel _channel;

  final ValueNotifier<AudioPreviewState> state =
      ValueNotifier<AudioPreviewState>(AudioPreviewState.idle);

  final ValueNotifier<Duration> position =
      ValueNotifier<Duration>(Duration.zero);

  final ValueNotifier<Duration> duration =
      ValueNotifier<Duration>(Duration.zero);

  final ValueNotifier<String?> currentUrl = ValueNotifier<String?>(null);

  final ValueNotifier<String?> errorMessage = ValueNotifier<String?>(null);

  Timer? _progressTimer;

  bool get isPlaying => state.value == AudioPreviewState.playing;
  bool get isBuffering => state.value == AudioPreviewState.buffering;

  /// 播放指定直链音频
  Future<void> play(String url, {Map<String, String>? headers}) async {
    if (url.isEmpty) return;

    if (currentUrl.value == url && state.value == AudioPreviewState.paused) {
      await resume();
      return;
    }

    currentUrl.value = url;
    state.value = AudioPreviewState.buffering;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    errorMessage.value = null;

    try {
      final args = <String, dynamic>{'url': url};
      if (headers != null) {
        args['headers'] = headers;
      }
      await _channel.invokeMethod('play', args);
    } on MissingPluginException {
      // 兼容测试环境
      state.value = AudioPreviewState.playing;
      _startProgressTimer();
    } catch (e) {
      state.value = AudioPreviewState.error;
      errorMessage.value = e.toString();
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    _stopProgressTimer();
    try {
      await _channel.invokeMethod('pause');
      state.value = AudioPreviewState.paused;
    } on MissingPluginException {
      state.value = AudioPreviewState.paused;
    } catch (e) {
      debugPrint('[AudioPreviewService] pause error: $e');
    }
  }

  /// 恢复播放
  Future<void> resume() async {
    try {
      await _channel.invokeMethod('play', {
        'url': currentUrl.value,
      });
      state.value = AudioPreviewState.playing;
      _startProgressTimer();
    } on MissingPluginException {
      state.value = AudioPreviewState.playing;
    } catch (e) {
      debugPrint('[AudioPreviewService] resume error: $e');
    }
  }

  /// 跳转到指定播放进度
  Future<void> seek(Duration target) async {
    position.value = target;
    try {
      await _channel.invokeMethod('seek', {
        'position': target.inMilliseconds,
      });
    } on MissingPluginException {
      // 兼容测试环境
    } catch (e) {
      debugPrint('[AudioPreviewService] seek error: $e');
    }
  }

  /// 停止播放并重置状态
  Future<void> stop() async {
    _stopProgressTimer();
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    state.value = AudioPreviewState.idle;
    currentUrl.value = null;
    position.value = Duration.zero;
  }

  /// 处理来自原生层的状态与进度回调
  Future<void> _handleNativeCall(MethodCall call) async {
    if (call.method == 'onPlayerStateChanged') {
      final args = call.arguments as Map?;
      final stateStr = args?['state']?.toString();
      final durMs = args?['duration'] as int?;
      final err = args?['message']?.toString();

      if (durMs != null && durMs > 0) {
        duration.value = Duration(milliseconds: durMs);
      }

      switch (stateStr) {
        case 'buffering':
          state.value = AudioPreviewState.buffering;
          break;
        case 'playing':
          state.value = AudioPreviewState.playing;
          _startProgressTimer();
          break;
        case 'paused':
          state.value = AudioPreviewState.paused;
          _stopProgressTimer();
          break;
        case 'completed':
          state.value = AudioPreviewState.completed;
          position.value = duration.value;
          _stopProgressTimer();
          break;
        case 'idle':
          state.value = AudioPreviewState.idle;
          _stopProgressTimer();
          break;
        case 'error':
          state.value = AudioPreviewState.error;
          errorMessage.value = err;
          _stopProgressTimer();
          break;
      }
    }
  }

  void _startProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (state.value != AudioPreviewState.playing) {
        _stopProgressTimer();
        return;
      }
      try {
        final res = await _channel.invokeMethod<Map>('getPosition');
        if (res != null) {
          final posMs = res['position'] as int? ?? 0;
          final durMs = res['duration'] as int? ?? 0;
          position.value = Duration(milliseconds: posMs);
          if (durMs > 0) {
            duration.value = Duration(milliseconds: durMs);
          }
        }
      } catch (_) {}
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// 释放服务与原生播放器资源
  void dispose() {
    _stopProgressTimer();
    stop();
    state.dispose();
    position.dispose();
    duration.dispose();
    currentUrl.dispose();
    errorMessage.dispose();
  }
}
