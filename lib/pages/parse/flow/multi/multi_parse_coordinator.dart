import 'package:dio/dio.dart';

import '../../../../models/history_item.dart';
import '../../../../models/parse/parse_status.dart';
import '../../../../models/common/batch_video_quality.dart';
import '../../../../models/save_page/selection/quality_indicator.dart';
import '../../../../models/save_page/selection/selection_state.dart';
import '../../../../models/save_page/work_kind.dart';
import '../../../../services/download/download_cancel_registry.dart';
import '../../../../services/media/video_downloader.dart';
import '../../../../services/selection/debug/selection_debug_bridge.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../../../services/selection/session_work_preparer.dart';
import '../../../../services/sniffer/lifecycle/sniff_cancelled_exception.dart';
import '../../../../widgets/save_page/middle_multi_work_sheet.dart';
import '../common/parse_flow_context.dart';
import '../common/parse_flow_helper.dart';
import '../common/parse_save_coordinator.dart';

/// 多作品批量解析协调器：多链接抓取、写入历史、中层选档选集与批量下载
class MultiParseCoordinator {
  const MultiParseCoordinator(this.ctx);

  final ParseFlowContext ctx;

  Future<void> parseMultiWorks(List<String> workUrls, String rawInput) async {
    try {
      ctx.logs.add('已识别 ${workUrls.length} 个作品链接，开始逐条捕获封面...');
      ctx.setStatus(
        ParseStatus.parsing(
          message: '已识别 ${workUrls.length} 个作品链接，开始逐条捕获封面...',
        ),
      );
      final extractResult = await ctx.sniffer.multiWork.extractWorks(
        workUrls,
        onProgress: (current, total, message) {
          if (!ctx.mounted) return;
          ctx.logs.upsertLast('正在抓取作品', message);
        },
        onLog: (message) {
          if (ctx.mounted) ctx.logs.add(message);
        },
      );
      if (!ctx.mounted || !ctx.isParsing()) return;

      ctx.logs.add(
        '作品封面捕获完成：${extractResult.works.length} 条可保存，'
        '${extractResult.filteredArticleCount} 条文章已过滤，'
        '${extractResult.failedCount} 条失败',
      );
      if (extractResult.failedUrls.isNotEmpty) {
        ctx.logs.add('未捕获成功的链接：${extractResult.failedUrls.join('、')}');
      }

      if (extractResult.works.isEmpty) {
        ctx.logs.add('未捕获到可保存的作品');
        ctx.setStatus(
          ParseStatus.failed(
            message: '未捕获到可保存的作品',
            failedUrls: extractResult.failedUrls.isNotEmpty
                ? extractResult.failedUrls
                : workUrls,
          ),
        );
        return;
      }

      final historyRecords = <HistoryItem>[];
      for (final work in extractResult.works) {
        final parsed = work.parsedResult;
        final desc = (parsed?.desc?.trim().isNotEmpty ?? false)
            ? parsed!.desc!.trim()
            : (work.title.trim().isNotEmpty ? work.title.trim() : work.url);
        historyRecords.add(
          HistoryItem(
            id: work.url,
            url: work.url,
            rawInput: rawInput,
            fullDesc: desc,
            title: work.title,
            coverUrl: work.coverUrl,
            isImagePost: work.kind == WorkMediaKind.image,
            mediaSummary: ParseFlowHelper.mediaSummaryFor(parsed, work.kind),
            itemCount: parsed?.items.length ?? 1,
          ),
        );
      }
      await ctx.stores.history.addRecords(historyRecords);
      if (!ctx.mounted || !ctx.isParsing()) return;

      ctx.setParsing(false);
      ctx.refresh();
      ctx.onRequestParseTab();

      final session = SaveSelectionSession.multiWork(
        works: extractResult.works,
        seed: ctx.stores.terminalMemory.seed,
        memoryStore: ctx.stores.terminalMemory,
      );
      SelectionDebugBridge.attach(session);

      try {
        if (!ctx.context.mounted) return;
        final confirmed = await MiddleMultiWorkSheet.show(
          ctx.context,
          session: session,
          secUid: SaveSelectionSession.syntheticSecUid,
          headers: ParseSaveCoordinator.mediaHeaders,
          nested: false,
          debugStore: ctx.stores.savePageDebug,
          onOpenWork: (workUrl, index) =>
              ctx.saveCoordinator.openWorkDetail(ctx.context, session, workUrl),
        );
        if (!ctx.context.mounted) return;
        if (confirmed != true) {
          ctx.logs.add('已取消多作品保存');
          ctx.setStatus(const ParseStatus.idle(message: '已取消多作品保存'));
          return;
        }

        final urls = session.allWorkUrls
            .where((url) => session.workState(url).isSelected)
            .toList();
        if (urls.isEmpty) {
          ctx.logs.add('未选择任何作品');
          ctx.setStatus(const ParseStatus.idle(message: '未选择任何作品'));
          return;
        }

        final qualityMode =
            session.terminal.quality.mode ?? BatchVideoQualityMode.highest;
        ctx.busy.value = true;
        final cancelToken = CancelToken();
        ctx.setDownloadCancelToken(cancelToken);
        DownloadCancelRegistry.attach(
          () => cancelToken.cancel('用户取消保存'),
        );
        ctx.logs.add('正在准备保存 ${urls.length} 个作品...');
        ctx.setStatus(ParseStatus.saving(message: '正在准备保存 ${urls.length} 个作品...'));

        final selected = await SessionWorkPreparer.prepare(
          session,
          urls,
          ctx.sniffer.sniffVideoUrl,
          isCancelled: () => cancelToken.isCancelled,
          onProgress: (current, total, label) => ctx.updateBatchSaveProgress(
            current,
            total,
            '正在准备保存 $current/$total：$label',
          ),
        );
        if (!ctx.mounted) return;
        if (cancelToken.isCancelled) {
          throw const DouyinDownloadCancelledException();
        }
        if (selected.isEmpty) {
          ctx.logs.add('选中作品没有可保存资源');
          ctx.setStatus(const ParseStatus.failed(message: '选中作品没有可保存资源'));
          return;
        }

        final startSaveMsg =
            '开始保存 ${selected.length} 个作品（${ParseFlowHelper.qualityLabel(qualityMode)}）...';
        ctx.logs.add(startSaveMsg);
        ctx.setStatus(ParseStatus.saving(message: startSaveMsg));
        final results = await ctx.workBatchSaver.saveWorks(
          selected,
          cancelToken: cancelToken,
          onProgress: ctx.updateBatchSaveProgress,
          onLog: (message) {
            if (ctx.mounted) ctx.logs.add(message);
          },
        );
        if (!ctx.mounted) return;

        final savedEntries = <String, String?>{
          for (final item in results)
            if (item.success) item.url: item.savedBaseName,
        };
        await ctx.stores.history.markSavedBatch(savedEntries);

        final successCount = results.where((item) => item.success).length;
        final finishMsg = '多作品保存完成：成功 $successCount/${results.length}';
        ctx.logs.add(finishMsg);
        final failed = [for (final r in results) if (!r.success) r.url];
        if (failed.isEmpty) {
          ctx.setStatus(ParseStatus.completed(message: finishMsg));
        } else {
          ctx.setStatus(
            ParseStatus.failed(message: finishMsg, failedUrls: failed),
          );
        }
      } finally {
        SelectionDebugBridge.detach(session);
        session.close();
      }
    } on DouyinDownloadCancelledException {
      if (ctx.mounted) {
        ctx.logs.add('已取消多作品保存');
        ctx.setStatus(const ParseStatus.idle(message: '已取消多作品保存'));
      }
    } on SniffCancelledException {
      if (ctx.mounted) {
        final cancelToken = ctx.getDownloadCancelToken();
        final msg =
            cancelToken?.isCancelled == true ? '已取消多作品保存' : '已取消解析';
        ctx.logs.add(msg);
        ctx.setStatus(ParseStatus.idle(message: msg));
      }
    } catch (e) {
      if (ctx.mounted) {
        final msg = '多作品保存失败：${ParseFlowHelper.friendlyError(e)}';
        ctx.logs.add(msg);
        ctx.setStatus(
          ParseStatus.failed(message: msg, failedUrls: workUrls, error: e),
        );
      }
    } finally {
      DownloadCancelRegistry.detach();
      ctx.setDownloadCancelToken(null);
      if (ctx.mounted) {
        ctx.busy.value = false;
        ctx.setParsing(false);
        ctx.refresh();
      }
    }
  }
}
