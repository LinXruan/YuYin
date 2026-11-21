import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/batch_video_quality.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/models/save_page/save_work_item.dart';
import 'package:yuyin/models/save_page/selection/aggregate_state.dart';
import 'package:yuyin/models/save_page/selection/selection_state.dart';
import 'package:yuyin/models/save_page/work_kind.dart';
import 'package:yuyin/models/single_work/media_download_item.dart';
import 'package:yuyin/models/single_work/single_work_result.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/utils/app_stores.dart';
import 'package:yuyin/utils/history/history_store.dart';

void main() {
  test('AppStores 多容器实例完全隔离，零静态状态串扰', () async {
    final storesA = AppStores(
      history: HistoryStore(skipSaveForTesting: true),
    );
    final storesB = AppStores(
      history: HistoryStore(skipSaveForTesting: true),
    );
    addTearDown(() {
      storesA.dispose();
      storesB.dispose();
    });

    await storesA.theme.setThemeMode(ThemeMode.dark);
    expect(storesA.theme.themeModeNotifier.value, ThemeMode.dark);
    expect(storesB.theme.themeModeNotifier.value, ThemeMode.system);

    await storesA.downloadSettings.setOnlyHighestQualityPerResolution(false);
    expect(storesA.downloadSettings.onlyHighestQualityPerResolution, isFalse);
    expect(storesB.downloadSettings.onlyHighestQualityPerResolution, isTrue);

    await storesA.saveLocation.updateLocation(
      MediaType.video,
      uri: 'content://tree/custom',
      displayPath: '/CustomVideo/',
    );
    expect(storesA.saveLocation.isAllDefault, isFalse);
    expect(storesB.saveLocation.isAllDefault, isTrue);

    await storesA.history.addRecord(
      HistoryItem(
        id: 'iso_1',
        url: 'https://www.douyin.com/video/iso_1',
        fullDesc: '容器 A 独占记录',
      ),
    );
    expect(storesA.history.records.length, 1);
    expect(storesB.history.records, isEmpty);

    await storesA.parseHint.setBatchHintDismissed(true);
    await storesA.loginState.setLoginPromptDismissed(true);
    expect(storesA.parseHint.batchHintDismissed, isTrue);
    expect(storesB.parseHint.batchHintDismissed, isFalse);
    expect(storesA.loginState.loginPromptDismissed, isTrue);
    expect(storesB.loginState.loginPromptDismissed, isFalse);

    storesA.savePageDebug.update('top', {'count': 1});
    expect(storesA.savePageDebug.snapshot, isNotNull);
    expect(storesB.savePageDebug.snapshot, isNull);
  });

  test('SaveSelectionSession.close 只写回注入的 TerminalMemoryStore 实例', () async {
    final storesA = AppStores();
    final storesB = AppStores();
    addTearDown(() {
      storesA.dispose();
      storesB.dispose();
    });

    final session = SaveSelectionSession.singleWork(
      work: const SaveWorkItem(url: 'v1', kind: WorkMediaKind.video),
      parsed: const SingleWorkResult(
        items: [
          MediaItem(
            url: 'v1#low',
            type: MediaType.video,
            resolution: '540x960',
            bitRate: 500000,
          ),
        ],
        cookie: '',
        isImagePost: false,
      ),
      seed: storesA.terminalMemory.seed,
      memoryStore: storesA.terminalMemory,
    );

    session.setTerminalKind(WorkMediaKind.video, SelectionState.none);
    session.close();
    await Future<void>.delayed(Duration.zero);

    expect(storesA.terminalMemory.seed.video, AggregateState.none);
    expect(storesB.terminalMemory.seed.video, AggregateState.all);
    expect(
      storesB.terminalMemory.seed.quality,
      BatchVideoQualityMode.highest,
    );
  });
}
