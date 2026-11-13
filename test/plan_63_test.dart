import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/common/save_memory_scope.dart';
import 'package:yuyin/models/media_item.dart';
import 'package:yuyin/models/save_page/author_works_selection.dart';
import 'package:yuyin/utils/download_settings_store.dart';
import 'package:yuyin/utils/save_selection_tree.dart';
import 'package:yuyin/utils/selection_mode_store.dart';
import 'package:yuyin/widgets/save_page/middle_multi_work_sheet.dart';
import 'package:yuyin/widgets/save_page/top_multi_home_sheet.dart';

SaveWorkItem _work(
  String url,
  WorkMediaKind kind, {
  WorkSelectionState state = WorkSelectionState.all,
  List<MediaItem> resources = const [],
  SingleWorkResult? parsed,
}) {
  return SaveWorkItem(
    url: url,
    kind: kind,
    selectionState: state,
    selectedResources: resources,
    parsedResult: parsed,
  );
}

SingleWorkResult _videoParsed() {
  return const SingleWorkResult(
    items: [
      MediaItem(
        url: 'https://cdn.example.com/low.mp4',
        type: MediaType.video,
        bitRate: 1000,
      ),
      MediaItem(
        url: 'https://cdn.example.com/high.mp4',
        type: MediaType.video,
        bitRate: 2000,
      ),
    ],
    cookie: 'cookie',
    isImagePost: false,
  );
}

SingleWorkResult _imageParsed() {
  return const SingleWorkResult(
    items: [
      MediaItem(url: 'https://cdn.example.com/1.jpg', type: MediaType.image),
      MediaItem(url: 'https://cdn.example.com/2.jpg', type: MediaType.image),
    ],
    cookie: 'cookie',
    isImagePost: true,
  );
}

void main() {
  setUp(() {
    SelectionModeStore.reset();
    DownloadSettingsStore.resetForTesting();
  });

  group('PLAN_63 选择树纯函数', () {
    test('作者全选/全不选递归设置作品并派生作者状态', () {
      final works = [
        _work('w1', WorkMediaKind.video, state: WorkSelectionState.none),
        _work('w2', WorkMediaKind.image, state: WorkSelectionState.none),
      ];

      final all = SaveSelectionTree.applyAuthorSelection(
        works,
        AuthorSelectionState.all,
      );
      expect(
        all.every((work) => work.selectionState == WorkSelectionState.all),
        isTrue,
      );
      expect(
        SaveSelectionTree.deriveAuthorState(all),
        AuthorSelectionState.all,
      );

      final none = SaveSelectionTree.applyAuthorSelection(
        all,
        AuthorSelectionState.none,
      );
      expect(
        none.every((work) => work.selectionState == WorkSelectionState.none),
        isTrue,
      );
      expect(
        SaveSelectionTree.deriveAuthorState(none),
        AuthorSelectionState.none,
      );
    });

    test('作品全选/全不选清空资源级选择，部分状态返回虚线', () {
      final work = _work(
        'w1',
        WorkMediaKind.image,
        state: WorkSelectionState.all,
        resources: const [
          MediaItem(url: 'a.jpg', type: MediaType.image),
        ],
      );

      final none = SaveSelectionTree.applyWorkSelection(
        work,
        WorkSelectionState.none,
      );
      expect(none.selectionState, WorkSelectionState.none);
      expect(none.selectedResources, isEmpty);

      final partial = SaveSelectionTree.applyBottomSelection(
        work,
        const [MediaItem(url: 'a.jpg', type: MediaType.image)],
        _imageParsed(),
      );
      expect(partial.selectionState, WorkSelectionState.partial);
    });

    test('画质聚合与批量切换', () {
      final works = [
        _work('v1', WorkMediaKind.video),
        _work('v2', WorkMediaKind.video),
      ];
      expect(
        SaveSelectionTree.aggregateQuality(works),
        BatchVideoQualityMode.highest,
      );

      final lowered = SaveSelectionTree.applyQualityToWorks(
        works,
        BatchVideoQualityMode.lowest,
      );
      expect(
        SaveSelectionTree.aggregateQuality(lowered),
        BatchVideoQualityMode.lowest,
      );
    });

    test('主页作品 parsedResult 为空时按已有状态保持，不误判 partial', () {
      final work = _work(
        'home-work',
        WorkMediaKind.image,
        state: WorkSelectionState.all,
      );
      final updated = SaveSelectionTree.applyBottomSelection(
        work,
        const [MediaItem(url: 'only.jpg', type: MediaType.image)],
        null,
      );
      expect(updated.selectionState, WorkSelectionState.all);
    });

    test('单个作品 specific 使上层聚合为 mixed', () {
      final works = [
        _work('v1', WorkMediaKind.video),
        _work(
          'v2',
          WorkMediaKind.video,
          resources: const [
            MediaItem(url: 'specific.mp4', type: MediaType.video),
          ],
        ).copyWith(
          qualityChoice: const WorkVideoQualityChoice.specific(
            MediaItem(url: 'specific.mp4', type: MediaType.video),
          ),
        ),
      ];
      expect(
        SaveSelectionTree.aggregateQuality(works),
        BatchVideoQualityMode.mixed,
      );
    });
  });

  group('PLAN_63 记忆隔离', () {
    test('三个底层作用域互不影响', () {
      SelectionModeStore.recordCategorySelection(
        MediaType.image,
        2,
        scope: SaveMemoryScope.homeBottom,
      );
      expect(
        SelectionModeStore.getBottomMode(
          MediaType.image,
          SaveMemoryScope.homeBottom,
        ),
        2,
      );
      expect(
        SelectionModeStore.getBottomMode(
          MediaType.image,
          SaveMemoryScope.multiBottom,
        ),
        1,
      );
      expect(
        SelectionModeStore.getBottomMode(
          MediaType.image,
          SaveMemoryScope.singleBottom,
        ),
        1,
      );
    });

    test('两个中层作用域互不影响', () {
      SelectionModeStore.setWorkCategoryMode(
        WorkMediaKind.video,
        2,
      );
      expect(
        SelectionModeStore.getMiddleCategoryMode(
          WorkMediaKind.video,
          SaveMemoryScope.multiMiddle,
        ),
        2,
      );
      expect(
        SelectionModeStore.getMiddleCategoryMode(
          WorkMediaKind.video,
          SaveMemoryScope.homeMiddle,
        ),
        1,
      );
    });

    test('三个画质作用域互不影响', () async {
      await DownloadSettingsStore.setBatchQuality(
        SaveMemoryScope.homeTop,
        BatchVideoQualityMode.lowest,
      );
      expect(
        DownloadSettingsStore.getBatchQuality(SaveMemoryScope.homeTop),
        BatchVideoQualityMode.lowest,
      );
      expect(
        DownloadSettingsStore.getBatchQuality(SaveMemoryScope.multiMiddle),
        BatchVideoQualityMode.highest,
      );
    });
  });

  group('PLAN_63 顶层选择树 UI', () {
    testWidgets('点击作者递归取消其作品，虚线由作品状态派生', (tester) async {
      final authors = [
        const MultiHomeAuthorItem(
          profile: UserHomeProfile(secUid: 'sec1', nickname: '作者一'),
        ),
        const MultiHomeAuthorItem(
          profile: UserHomeProfile(secUid: 'sec2', nickname: '作者二'),
        ),
      ];
      final works = {
        'sec1': [
          _work('w1', WorkMediaKind.video),
          _work('w2', WorkMediaKind.image),
        ],
        'sec2': [_work('w3', WorkMediaKind.video)],
      };

      final completer = Completer<MultiHomeSelectionResult?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    completer.complete(
                      await MultiHomePreviewSheet.show(
                        context,
                        authors: authors,
                        useMemoryDefault: false,
                        initialWorksBySecUid: works,
                      ),
                    );
                  },
                  child: const Text('open top'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open top'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey('author_tile_0')));
      await tester.pumpAndSettle();
      expect(find.text('已选 1 / 2 位作者'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('multi_home_confirm_btn')));
      await tester.pumpAndSettle();
      final result = await completer.future;

      expect(result, isNotNull);
      expect(
        result!.worksBySecUid['sec1']!
            .every((work) => work.selectionState == WorkSelectionState.none),
        isTrue,
      );
      expect(
        result.worksBySecUid['sec2']!
            .every((work) => work.selectionState == WorkSelectionState.all),
        isTrue,
      );
    });

    testWidgets('中层返回部分作品后顶层作者显示虚线', (tester) async {
      final authors = [
        const MultiHomeAuthorItem(
          profile: UserHomeProfile(secUid: 'sec1', nickname: '作者一'),
        ),
      ];
      final works = {
        'sec1': [
          _work('w1', WorkMediaKind.video),
          _work('w2', WorkMediaKind.video),
        ],
      };

      final completer = Completer<MultiHomeSelectionResult?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    completer.complete(
                      await MultiHomePreviewSheet.show(
                        context,
                        authors: authors,
                        useMemoryDefault: false,
                        initialWorksBySecUid: works,
                        onOpenAuthor: (author, index, currentWorks, qualityMode) async {
                          return AuthorWorksSelection(
                            works: [
                              works['sec1']![0],
                              works['sec1']![1].copyWith(
                                selectionState: WorkSelectionState.none,
                              ),
                            ],
                            qualityMode: BatchVideoQualityMode.highest,
                          );
                        },
                      ),
                    );
                  },
                  child: const Text('open top'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open top'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open_author_button_0')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('author_partial_border_0')),
        findsOneWidget,
      );
    });

    testWidgets('顶层作者与画质控制会传入进入中层的回调', (tester) async {
      final authors = [
        const MultiHomeAuthorItem(
          profile: UserHomeProfile(secUid: 'sec1', nickname: '作者一'),
        ),
      ];
      final works = {
        'sec1': [_work('v1', WorkMediaKind.video)],
      };
      List<SaveWorkItem>? passedWorks;
      BatchVideoQualityMode? passedQuality;

      final completer = Completer<MultiHomeSelectionResult?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    completer.complete(
                      await MultiHomePreviewSheet.show(
                        context,
                        authors: authors,
                        useMemoryDefault: false,
                        initialWorksBySecUid: works,
                        onOpenAuthor: (author, index, currentWorks, quality) async {
                          passedWorks = currentWorks;
                          passedQuality = quality;
                          return AuthorWorksSelection(
                            works: currentWorks,
                            qualityMode: quality,
                          );
                        },
                      ),
                    );
                  },
                  child: const Text('open top'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open top'));
      await tester.pumpAndSettle();

      // 顶层切最低画质
      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();
      // 顶层取消作者 -> 作品应全部未选
      await tester.tap(find.byKey(const ValueKey('author_tile_0')));
      await tester.pumpAndSettle();
      // 进入中层回调
      await tester.tap(find.byKey(const ValueKey('open_author_button_0')));
      await tester.pumpAndSettle();

      expect(passedWorks, isNotNull);
      expect(
        passedWorks!.every(
          (work) => work.selectionState == WorkSelectionState.none,
        ),
        isTrue,
      );
      expect(passedQuality, BatchVideoQualityMode.lowest);
      expect(
        passedWorks!.every(
          (work) => work.qualityChoice.level == WorkVideoQualityLevel.lowest,
        ),
        isTrue,
      );
    });
  });

  group('PLAN_63 中层选择树 UI', () {
    testWidgets('底层返回部分资源后中层虚线并显示混合画质', (tester) async {
      final parsed = _videoParsed();
      final works = [
        SaveWorkItem(
          url: 'v1',
          kind: WorkMediaKind.video,
          parsedResult: parsed,
        ),
      ];

      final completer = Completer<MultiWorkSelectionResult?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    completer.complete(
                      await MiddleMultiWorkSheet.show(
                        context,
                        works: works,
                        useMemoryDefault: false,
                        onOpenWork: (work, index) async {
                          return const WorkDetailSelection(
                            state: WorkSelectionState.partial,
                            selectedResources: [
                              MediaItem(
                                url: 'https://cdn.example.com/high.mp4',
                                type: MediaType.video,
                              ),
                            ],
                            qualityChoice: WorkVideoQualityChoice.specific(
                              MediaItem(
                                url: 'https://cdn.example.com/high.mp4',
                                type: MediaType.video,
                              ),
                            ),
                            parsedResult: null,
                          );
                        },
                      ),
                    );
                  },
                  child: const Text('open middle'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open middle'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('open_work_button_0')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('work_partial_border_0')),
        findsOneWidget,
      );
      expect(find.text('混合画质'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('middle_save_button')));
      await tester.pumpAndSettle();
      final result = await completer.future;
      expect(result, isNotNull);
      expect(result!.qualityMode, BatchVideoQualityMode.mixed);
      expect(
        result.selectedWorks.single.selectedResources.single.url,
        'https://cdn.example.com/high.mp4',
      );
    });
  });

  group('PLAN_63 顶层混合画质', () {
    testWidgets('下层 specific 使顶层显示混合画质，顶层切换后清空旧档位', (tester) async {
      final authors = [
        const MultiHomeAuthorItem(
          profile: UserHomeProfile(secUid: 'sec1', nickname: '作者一'),
        ),
      ];
      final works = {
        'sec1': [
          _work('v1', WorkMediaKind.video),
          _work('v2', WorkMediaKind.video, resources: const [
            MediaItem(url: 'specific.mp4', type: MediaType.video),
          ]).copyWith(
            qualityChoice: const WorkVideoQualityChoice.specific(
              MediaItem(url: 'specific.mp4', type: MediaType.video),
            ),
          ),
        ],
      };

      final completer = Completer<MultiHomeSelectionResult?>();
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    completer.complete(
                      await MultiHomePreviewSheet.show(
                        context,
                        authors: authors,
                        useMemoryDefault: false,
                        initialWorksBySecUid: works,
                      ),
                    );
                  },
                  child: const Text('open top'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open top'));
      await tester.pumpAndSettle();
      expect(find.text('混合画质'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('quality_toggle_btn')));
      await tester.pumpAndSettle();
      expect(find.text('最高画质'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('multi_home_confirm_btn')));
      await tester.pumpAndSettle();
      final result = await completer.future;
      expect(result, isNotNull);
      expect(
        result!.worksBySecUid['sec1']!
            .every((work) => work.selectedResources.isEmpty),
        isTrue,
      );
      expect(
        result.worksBySecUid['sec1']!.every(
          (work) =>
              work.qualityChoice.level == WorkVideoQualityLevel.highest,
        ),
        isTrue,
      );
    });
  });
}
