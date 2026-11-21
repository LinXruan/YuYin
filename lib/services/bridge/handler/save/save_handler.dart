import 'dart:io';

import '../../../../models/history/history_record_type.dart';
import '../../../../models/history_item.dart';
import '../../../../models/save_page/save_work_item.dart';
import '../../../../models/save_page/selection/terminal_seed.dart';
import '../../../../models/save_page/work_kind.dart';
import '../../../../utils/history/history_store.dart';
import '../../../../utils/memory/terminal_memory_store.dart';
import '../../../../utils/save/author_folder_name.dart';
import '../../../../utils/save/home_save_path.dart';
import '../../../../utils/url/batch_input_parser.dart';
import '../../../../utils/url/url_classifier.dart';
import '../../../batch_work/work_batch_saver.dart';
import '../../../selection/save_selection_session.dart';
import '../../../selection/session_work_preparer.dart';
import '../../server/agent_automation_server.dart';

/// 批量保存端点：多作品与主页作者目录。
class SaveHandler {
  SaveHandler(this.server);

  final AgentAutomationServer server;

  /// POST /api/save/works：解析多作品链接并批量保存到当前单作品路径
  Future<void> handleSaveWorks(HttpRequest request) async {
    final sniffer = server.sniffer;
    final downloader = server.downloader;
    if (sniffer == null || downloader == null) {
      server.sendJson(request, HttpStatus.serviceUnavailable, {
        'error': '捕获服务未初始化',
      });
      return;
    }

    final body = await server.readJsonBody(request);
    final text = body['text']?.toString() ?? '';
    if (text.trim().isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': 'text is required',
      });
      return;
    }

    final batch = DouyinBatchInputParser.parseBatchInput(text);
    if (batch.workUrls.isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': '未识别到作品链接',
      });
      return;
    }

    server.busy.value = true;
    try {
      server.logs.add('批量保存作品：${batch.workUrls.length} 条');
      final extract = await sniffer.multiWork.extractWorks(
        batch.workUrls,
        onLog: server.logs.add,
      );
      final records = <HistoryItem>[];
      for (final work in extract.works) {
        final parsed = work.parsedResult;
        final desc = (parsed?.desc?.trim().isNotEmpty ?? false)
            ? parsed!.desc!.trim()
            : (work.title.trim().isNotEmpty ? work.title.trim() : work.url);
        records.add(
          HistoryItem(
            id: work.url,
            url: work.url,
            rawInput: text,
            fullDesc: desc,
            title: work.title,
            coverUrl: work.coverUrl,
            isImagePost: work.kind == WorkMediaKind.image,
            mediaSummary:
                work.kind == WorkMediaKind.image ? '图集/文案' : '视频/文案',
            itemCount: parsed?.items.length ?? 1,
          ),
        );
      }
      await HistoryStore.addRecords(records);

      final quality = server.qualityModeFrom(body['quality']?.toString());
      final memory = TerminalMemoryStore.seed;
      final session = SaveSelectionSession.multiWork(
        works: extract.works,
        seed: TerminalSeed(
          picture: memory.picture,
          live: memory.live,
          music: memory.music,
          video: memory.video,
          quality: quality,
        ),
      );
      final selected = await SessionWorkPreparer.prepare(
        session,
        extract.works.map((work) => work.url),
        sniffer.sniffVideoUrl,
      );
      session.dispose();
      final saver = WorkBatchSaver(downloader: downloader);
      final results = await saver.saveWorks(selected, onLog: server.logs.add);
      for (final result in results) {
        if (result.success) {
          await HistoryStore.markSavedWithMeta(
            result.url,
            savedBaseName: result.savedBaseName,
          );
        }
      }
      server.sendJson(request, HttpStatus.ok, {
        'count': results.length,
        'successCount': results.where((item) => item.success).length,
        'results': results.map(server.serializeWorkSaveResult).toList(),
        'logs': server.logs.logs,
      });
    } catch (e) {
      server.logs.add('批量保存作品失败: $e');
      server.sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
      });
    } finally {
      server.busy.value = false;
    }
  }

  /// POST /api/save/home：解析主页并批量保存到作者分类目录
  Future<void> handleSaveHome(HttpRequest request) async {
    final sniffer = server.sniffer;
    final downloader = server.downloader;
    if (sniffer == null || downloader == null) {
      server.sendJson(request, HttpStatus.serviceUnavailable, {
        'error': '捕获服务未初始化',
      });
      return;
    }

    final body = await server.readJsonBody(request);
    final url = body['url']?.toString() ?? '';
    if (url.trim().isEmpty) {
      server.sendJson(request, HttpStatus.badRequest, {
        'error': 'url is required',
      });
      return;
    }

    server.busy.value = true;
    try {
      server.logs.add('主页批量保存：$url');
      final home = await sniffer.userHome.extractAllWorks(url);
      final works = <SaveWorkItem>[];
      for (final workUrl in home.workUrls) {
        if (DouyinUrlClassifier.isArticleUrl(workUrl)) continue;
        final kind = DouyinUrlClassifier.classifyWorkPage(workUrl) == DouyinWorkPage.note
            ? WorkMediaKind.image
            : WorkMediaKind.video;
        works.add(
          SaveWorkItem(
            url: workUrl,
            kind: kind,
            title: home.getTitle(workUrl) ?? '',
            coverUrl: home.getCover(workUrl) ?? '',
          ),
        );
      }

      final totalWorks = works.length;
      final limit = (body['limit'] as num?)?.toInt() ?? 0;
      if (limit > 0 && works.length > limit) {
        works.removeRange(limit, works.length);
      }

      if (works.isEmpty) {
        server.sendJson(request, HttpStatus.ok, {
          'secUid': home.secUid,
          'nickname': home.nickname,
          'count': 0,
          'successCount': 0,
          'results': const [],
        });
        return;
      }

      await HistoryStore.addRecord(
        HistoryItem(
          id: 'home:${home.secUid}',
          url: 'https://www.douyin.com/user/${home.secUid}',
          rawInput: url,
          fullDesc: home.nickname,
          title: home.nickname,
          coverUrl: home.avatarUrl,
          mediaSummary: '作者主页',
          itemCount: totalWorks,
          recordType: HistoryRecordType.userHome,
          authorSecUid: home.secUid,
        ),
      );

      final authorFolder = AuthorFolderName.resolve(home.nickname, home.secUid);
      final config = server.stores.saveLocation.current;
      final quality = server.qualityModeFrom(body['quality']?.toString());
      final memory = TerminalMemoryStore.seed;
      final session = SaveSelectionSession.home(
        profiles: [home.profile],
        worksBySecUid: {home.secUid: works},
        seed: TerminalSeed(
          picture: memory.picture,
          live: memory.live,
          music: memory.music,
          video: memory.video,
          quality: quality,
        ),
      );
      final selected = await SessionWorkPreparer.prepare(
        session,
        works.map((work) => work.url),
        sniffer.sniffVideoUrl,
      );
      session.dispose();
      final saver = WorkBatchSaver(downloader: downloader);
      final results = await saver.saveWorks(
        selected,
        targetResolver: (type) =>
            HomeSavePath.buildTarget(config, type, authorFolder),
        onLog: server.logs.add,
      );
      if (results.any((item) => item.success)) {
        await HistoryStore.markSaved('home:${home.secUid}', true);
      }
      server.sendJson(request, HttpStatus.ok, {
        'secUid': home.secUid,
        'nickname': home.nickname,
        'authorFolder': authorFolder,
        'count': results.length,
        'successCount': results.where((item) => item.success).length,
        'results': results.map(server.serializeWorkSaveResult).toList(),
        'logs': server.logs.logs,
      });
    } catch (e) {
      server.logs.add('主页批量保存失败: $e');
      server.sendJson(request, HttpStatus.internalServerError, {
        'error': '$e',
      });
    } finally {
      server.busy.value = false;
    }
  }
}