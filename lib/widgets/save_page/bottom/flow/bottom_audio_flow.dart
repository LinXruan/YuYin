part of '../../bottom_media_sheet.dart';

// ignore_for_file: unnecessary_this

/// bottom audio flow
extension _SheetBottomAudioFlowFlow on _ImagePreviewSheetState {
  void _togglePlayAudio(MediaItem item) {
    if (_currentPlayingItem?.url == item.url) {
      if (_audioService.isPlaying) {
        _audioService.pause();
      } else {
        _audioService.play(item.url, headers: widget.headers);
      }
    } else {
      _currentPlayingItem = item;
      _showAudioPlayerBar = true;
      _audioService.play(item.url, headers: widget.headers);
    }
    _refresh(() {});
  }

  /// 关闭底部播放条并停止播放

  void _closeAudioPlayerBar() {
    _audioService.stop();
    _refresh(() {
      _showAudioPlayerBar = false;
      _currentPlayingItem = null;
    });
  }
}
