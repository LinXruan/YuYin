part of '../../bottom_media_sheet.dart';

/// 底层音频试听
extension _BottomAudioFlow on _ImagePreviewSheetState {
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

  void _closeAudioPlayerBar() {
    _audioService.stop();
    _refresh(() {
      _showAudioPlayerBar = false;
      _currentPlayingItem = null;
    });
  }
}