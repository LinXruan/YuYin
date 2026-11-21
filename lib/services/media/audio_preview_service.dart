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
  DateTime? _seekGuardUntil;
  bool _disposed = false;
  Map<String, String>? _lastHeaders;

  bool get isPlaying => state.value == AudioPreviewState.playing;
  bool get isBuffering => state.value == AudioPreviewState.buffering;

  /// 播放指定直链音频
  Future<void> play(String url, {Map<String, String>? headers}) async {
    if (_disposed || url.isEmpty) return;

    if (currentUrl.value == url && state.value == AudioPreviewState.paused) {
      await resume();
      return;
    }

    _lastHeaders = headers ?? _lastHeaders;
    currentUrl.value = url;
    state.value = AudioPreviewState.buffering;
    position.value = Duration.zero;
    duration.value = Duration.zero;
    errorMessage.value = null;

    try {
      final args = <String, dynamic>{'url': url};
      final merged = _lastHeaders;
      if (merged != null && merged.isNotEmpty) {
        args['headers'] = merged;
      }
      await _channel.invokeMethod('play', args);
    } on MissingPluginException {
      if (_disposed) return;
      // 兼容测试环境
      state.value = AudioPreviewState.playing;
      _startProgressTimer();
    } catch (e) {
      if (_disposed) return;
      state.value = AudioPreviewState.error;
      errorMessage.value = e.toString();
    }
  }

  /// 暂停播放
  Future<void> pause() async {
    if (_disposed) return;
    _stopProgressTimer();
    try {
      await _channel.invokeMethod('pause');
      if (_disposed) return;
      state.value = AudioPreviewState.paused;
    } on MissingPluginException {
      if (_disposed) return;
      state.value = AudioPreviewState.paused;
    } catch (e) {
      debugPrint('[AudioPreviewService] pause error: $e');
    }
  }

  /// 恢复播放：携原请求头重建原生播放器时仍可正常取流
  Future<void> resume() async {
    if (_disposed) return;
    final url = currentUrl.value;
    if (url == null || url.isEmpty) return;
    try {
      final args = <String, dynamic>{'url': url};
      final merged = _lastHeaders;
      if (merged != null && merged.isNotEmpty) {
        args['headers'] = merged;
      }
      await _channel.invokeMethod('play', args);
      if (_disposed) return;
      state.value = AudioPreviewState.playing;
      errorMessage.value = null;
      _startProgressTimer();
    } on MissingPluginException {
      if (_disposed) return;
      state.value = AudioPreviewState.playing;
    } catch (e) {
      if (_disposed) return;
      state.value = AudioPreviewState.error;
      errorMessage.value = e.toString();
    }
  }

  /// 跳转到指定播放进度
  Future<void> seek(Duration target) async {
    if (_disposed) return;
    _seekGuardUntil = DateTime.now().add(const Duration(milliseconds: 450));
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
    if (_disposed) return;
    _stopProgressTimer();
    _seekGuardUntil = null;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
    if (_disposed) return;
    state.value = AudioPreviewState.idle;
    currentUrl.value = null;
    position.value = Duration.zero;
  }

  /// 处理来自原生层的状态与进度回调
  Future<void> _handleNativeCall(MethodCall call) async {
    if (_disposed) return;
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
          errorMessage.value = null;
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
    if (_disposed) return;
    _progressTimer?.cancel();
    _progressTimer = Timer.periodic(const Duration(milliseconds: 300), (_) async {
      if (_disposed) return;
      if (state.value != AudioPreviewState.playing) {
        _stopProgressTimer();
        return;
      }
      try {
        final res = await _channel.invokeMethod<Map>('getPosition');
        if (_disposed ||
            res == null ||
            state.value != AudioPreviewState.playing) {
          return;
        }
        final guard = _seekGuardUntil;
        if (guard != null && DateTime.now().isBefore(guard)) {
          return;
        }
        final posMs = res['position'] as int? ?? 0;
        final durMs = res['duration'] as int? ?? 0;
        position.value = Duration(milliseconds: posMs);
        if (durMs > 0) {
          duration.value = Duration(milliseconds: durMs);
        }
      } catch (_) {}
    });
  }

  void _stopProgressTimer() {
    _progressTimer?.cancel();
    _progressTimer = null;
  }

  /// 释放服务与原生播放器资源
  ///
  /// 先置销毁标记并注销 Channel，再发一次 fire-and-forget 的 stop，
  /// 避免异步回调在 Notifier 销毁后写状态。
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _stopProgressTimer();
    _channel.setMethodCallHandler(null);
    unawaited(_channel.invokeMethod<void>('stop').catchError((_) {}));
    state.dispose();
    position.dispose();
    duration.dispose();
    currentUrl.dispose();
    errorMessage.dispose();
  }
}
