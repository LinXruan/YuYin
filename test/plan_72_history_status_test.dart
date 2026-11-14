import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history/history_record_type.dart';
import 'package:yuyin/models/history/history_saved_state.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/utils/history/history_store.dart';

void main() {
  setUp(() {
    HistoryStore.resetForTesting(skipSave: true);
  });

  group('HistorySavedState', () {
    test('作者任意作品成功即已保存', () {
      expect(
        HistorySavedState.resolveAuthorSaved([true, false, false]),
        isTrue,
      );
      expect(
        HistorySavedState.resolveAuthorSaved([false, false]),
        isFalse,
      );
      expect(HistorySavedState.resolveAuthorSaved(const []), isFalse);
    });

    test('作品任意资源成功即已保存', () {
      expect(HistorySavedState.resolveWorkSaved(1), isTrue);
      expect(HistorySavedState.resolveWorkSaved(0), isFalse);
    });
  });

  group('HistoryStore.markSaved', () {
    test('主页记录按 id 匹配', () async {
      await HistoryStore.addRecord(
        HistoryItem(
          id: 'home:sec1',
          url: 'https://www.douyin.com/user/sec1',
          fullDesc: '作者',
          recordType: HistoryRecordType.userHome,
          authorSecUid: 'sec1',
        ),
      );

      await HistoryStore.markSaved('home:sec1');

      expect(HistoryStore.records.single.isSaved, isTrue);
    });

    test('主页记录 id 不匹配时按 authorSecUid 兜底', () async {
      await HistoryStore.addRecord(
        HistoryItem(
          id: 'legacy-id',
          url: '',
          fullDesc: '作者',
          recordType: HistoryRecordType.userHome,
          authorSecUid: 'sec2',
        ),
      );

      await HistoryStore.markSaved('home:sec2');

      expect(HistoryStore.records.single.isSaved, isTrue);
    });
  });
}
