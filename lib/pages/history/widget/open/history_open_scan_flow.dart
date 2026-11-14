import '../../../../models/history/saved_media_availability.dart';
import '../../../../models/history_item.dart';
import '../../../../services/history/album_locator.dart';

typedef HistoryMediaScanner = Future<List<SavedMediaAvailability>> Function(
  HistoryItem item,
);
typedef HistoryMediaOpener = Future<bool> Function(
  SavedMediaAvailability availability,
);

/// 历史跳转的扫描与打开策略，可注入以便 Widget 测试。
class HistoryOpenScanFlow {
  HistoryOpenScanFlow({
    HistoryMediaScanner? scanner,
    HistoryMediaOpener? opener,
  })  : _scanner = scanner ?? ((item) => AlbumLocator.scan(item)),
        _opener = opener ?? ((availability) => AlbumLocator.open(availability));

  final HistoryMediaScanner _scanner;
  final HistoryMediaOpener _opener;

  Future<List<SavedMediaAvailability>> scan(HistoryItem item) =>
      _scanner(item);

  Future<bool> open(SavedMediaAvailability availability) =>
      _opener(availability);
}
