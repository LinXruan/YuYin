import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yuyin/models/history_item.dart';
import 'package:yuyin/models/common/work_type.dart';
import 'package:yuyin/models/save_page/save_work_item.dart';
import 'package:yuyin/models/save_page/selection/terminal_seed.dart';
import 'package:yuyin/models/save_page/work_kind.dart';
import 'package:yuyin/models/single_work/media_download_item.dart';
import 'package:yuyin/models/single_work/single_work_result.dart';
import 'package:yuyin/models/update/app_update_status.dart';
import 'package:yuyin/services/media/audio_preview_service.dart';
import 'package:yuyin/services/selection/save_selection_session.dart';
import 'package:yuyin/services/update/parser/update_atom_parser.dart';
import 'package:yuyin/services/update/version/update_version.dart';
import 'package:yuyin/utils/atomic_file_writer.dart';
import 'package:yuyin/utils/history/history_store.dart';
import 'package:yuyin/utils/save/author_folder_name.dart';

Future<Directory> _tempDir(String prefix) =>
    Directory.systemTemp.createTemp(prefix);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AtomicFileWriter 原子写', () {
    late Directory dir;

    setUp(() async {
      dir = await _tempDir('yuyin_atomic_');
    });

    tearDown(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    test('同一路径并发写入按调用顺序串行落盘', () async {
      final file = File('${dir.path}/records.json');
      final writes = <Future<void>>[
        for (var i = 0; i < 20; i++)
          AtomicFileWriter.writeString(file, '{"index":$i}'),
      ];
      await Future.wait(writes);

      expect(await file.readAsString(), '{"index":19}');
      expect(AtomicFileWriter.hasPendingWrites, isFalse);
    });

    test('主文件损坏时从 .bak 恢复并回写', () async {
      final file = File('${dir.path}/records.json');
      await AtomicFileWriter.writeString(file, '{"version":1}');
      await AtomicFileWriter.writeString(file, '{"version":2}');
      await file.writeAsString('{"version":');

      final recovered = await AtomicFileWriter.readString(
        file,
        isValid: (content) {
          try {
            return content.startsWith('{') && content.endsWith('}');
          } catch (_) {
            return false;
          }
        },
      );

      expect(recovered, '{"version":1}');
      expect(await file.readAsString(), '{"version":1}');
    });

    test('删除会同时清理主文件与临时/备份副本', () async {
      final file = File('${dir.path}/flag.json');
      await AtomicFileWriter.writeString(file, '1');
      await AtomicFileWriter.writeString(file, '2');
      await AtomicFileWriter.delete(file);

      expect(await file.exists(), isFalse);
      expect(await File('${file.path}.bak').exists(), isFalse);
      expect(await File('${file.path}.tmp').exists(), isFalse);
    });
  });

  group('HistoryStore 批量落盘', () {
    late Directory dir;
    late HistoryStore store;

    setUpAll(() async {
      dir = await _tempDir('yuyin_history_');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        const MethodChannel('plugins.flutter.io/path_provider'),
        (MethodCall call) async => dir.path,
      );
    });

    tearDownAll(() async {
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
    });

    setUp(() {
      store = HistoryStore();
    });

    tearDown(() {
      store.dispose();
    });

    test('addRecords 一次写入全部记录并去重', () async {
      await store.addRecords([
        for (var i = 0; i < 10; i++)
          HistoryItem(
            id: 'id$i',
            url: 'https://www.douyin.com/video/$i',
            fullDesc: '',
          ),
      ]);
      expect(store.records.length, 10);

      await store.addRecords([
        HistoryItem(
          id: 'id3',
          url: 'https://www.douyin.com/video/3',
          fullDesc: '',
        ),
      ]);
      expect(store.records.length, 10);
      expect(store.records.first.id, 'id3');
    });

    test('markSavedBatch 单次应用保存状态与文件基名', () async {
      await store.addRecords([
        HistoryItem(id: 'a', url: 'ua', fullDesc: ''),
        HistoryItem(id: 'b', url: 'ub', fullDesc: ''),
      ]);

      await store.markSavedBatch({'a': '视频A', 'b': null});

      final a = store.records.firstWhere((item) => item.id == 'a');
      final b = store.records.firstWhere((item) => item.id == 'b');
      expect(a.isSaved, isTrue);
      expect(a.savedBaseName, '视频A');
      expect(b.isSaved, isTrue);
    });

    test('文件损坏后 init 可从 .bak 恢复', () async {
      await store.addRecords([
        HistoryItem(id: 'a', url: 'ua', fullDesc: '第一条'),
      ]);
      await store.addRecords([
        HistoryItem(id: 'b', url: 'ub', fullDesc: '第二条'),
      ]);
      final file = File('${dir.path}/history_records.json');
      await file.writeAsString('[{"id":');

      store.resetForTesting();
      await store.init();

      expect(store.records.length, 1);
      expect(store.records.first.id, 'a');
    });
  });

  group('作者文件夹名', () {
    test('按码点截断不劈裂 Emoji', () {
      final name = AuthorFolderName.truncateByRunes('昵称😀😀😀', 4);
      expect(name, '昵称😀😀');
      expect(name.codeUnits.any((unit) => unit == 0xFFFD), isFalse);
    });

    test('超长昵称截断后不以空格或点结尾', () {
      final name = AuthorFolderName.resolve('${'长' * 60} ...', 'sec');
      expect(name.length, lessThanOrEqualTo(40));
      expect(name.endsWith('.'), isFalse);
      expect(name.endsWith(' '), isFalse);
    });
  });

  group('更新版本与 Atom 解析', () {
    test('预发布版本小于同号正式版', () {
      expect(UpdateVersion.compareVersion('1.5.8-beta', '1.5.8'), lessThan(0));
      expect(UpdateVersion.compareVersion('1.5.8', '1.5.8-beta'), greaterThan(0));
      expect(UpdateVersion.compareVersion('1.5.8', '1.5.7'), greaterThan(0));
      expect(UpdateVersion.cleanVersion('v1.5.8+192'), '1.5.8');
    });

    test('Atom 版本取自 releases/tag 链接而非 title', () {
      const xml = '''
<feed><entry>
  <title>日常发布说明</title>
  <link rel="alternate" href="https://github.com/LinXruan/YuYin/releases/tag/v1.6.0"/>
  <updated>2026-11-20T10:00:00Z</updated>
  <content type="html">&lt;p&gt;修复若干问题&lt;/p&gt;</content>
</entry></feed>''';

      final info = UpdateAtomParser.parseAtomFeed(xml, '1.5.8+192');
      expect(info, isNotNull);
      expect(info!.version, '1.6.0');
      expect(info.tagName, 'v1.6.0');
      expect(info.hasUpdate, isTrue);
      expect(
        info.getDownloadUrl(preferArm64: true),
        contains('/releases/download/v1.6.0/'),
      );
    });
  });

  group('会话关闭后不再写状态', () {
    test('close 后的 ingest 与 setTier 安全返回', () {
      final session = SaveSelectionSession.singleWork(
        work: const SaveWorkItem(
          url: 'https://www.douyin.com/video/1',
          kind: WorkMediaKind.video,
        ),
        parsed: const SingleWorkResult(
          items: [
            MediaItem(url: 'v1', type: MediaType.video, resolution: '720p'),
          ],
          cookie: '',
          isImagePost: false,
        ),
        seed: const TerminalSeed(),
      );
      final revision = session.revision;

      session.close();

      expect(
        () => session.setTier(
          'https://www.douyin.com/video/1',
          'v1',
        ),
        returnsNormally,
      );
      expect(session.revision, revision);
    });
  });

  group('音频服务销毁', () {
    const channel = MethodChannel('test/yuyin_audio');

    setUp(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (MethodCall call) async => null);
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('dispose 后迟到回调与重复调用均不抛异常', () async {
      final service = AudioPreviewService(channel: channel);
      await service.play('https://example.com/a.mp3');
      service.dispose();

      expect(() => service.dispose(), returnsNormally);
      expect(() => service.play('https://example.com/b.mp3'), returnsNormally);
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('更新状态模型', () {
    test('copyWith(clearError) 可以清空失败文案', () {
      const status = AppUpdateStatus(errorMessage: '下载失败');
      final cleared = status.copyWith(clearError: true);
      expect(cleared.errorMessage, isNull);

      final kept = status.copyWith(progress: 0.5);
      expect(kept.errorMessage, '下载失败');
    });
  });
}