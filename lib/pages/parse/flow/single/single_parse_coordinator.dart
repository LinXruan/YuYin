import 'package:dio/dio.dart';

import '../../../../models/common/work_type.dart';
import '../../../../models/history_item.dart';
import '../../../../models/save_page/save_work_item.dart';
import '../../../../models/save_page/selection/selected_work.dart';
import '../../../../models/save_page/work_kind.dart';
import '../../../../models/single_work/single_work_result.dart';
import '../../../../services/download/download_cancel_registry.dart';
import '../../../../services/media/video_downloader.dart';
import '../../../../services/selection/debug/selection_debug_bridge.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../../../services/sniffer/lifecycle/sniff_cancelled_exception.dart';
import '../../../../utils/history/history_store.dart';
import '../../../../utils/memory/terminal_memory_store.dart';
import '../../../../utils/save/file_name_formatter.dart';
import '../../../../utils/savelocation/save_location_store.dart';
import '../../../../utils/url/url_extractor.dart';
import '../../../../widgets/save_page/bottom_media_sheet.dart';
import '../common/parse_flow_context.dart';
import '../common/parse_flow_helper.dart';
import '../common/parse_save_coordinator.dart';

/// 单作品解析协调器：单链接抓取、写入历史、弹窗选档与落地下载
class SingleParseCoordinator {
  const SingleParseCoordinator(this.ctx);

  final ParseFlowContext ctx;

  Future<void> parseSingleWork(String url, String rawInput) async {
    try {
      ctx.logs.add('正在解析作品...');
      final result = await ctx.sniffer.sniffVideoUrl(url);
      if (!ctx.mounted || !ctx.isParsing()) return;
      ctx.setParsing(false);
      ctx.refresh();

      if (result.items.isEmpty) {
        ctx.logs.add('未解析到可下载资源，请检查链接或稍后重试');
        return;
      }

      final historyDesc = (result.desc?.trim().isNotEmpty ?? false)
          ? result.desc!.trim()
          : (result.title?.trim().isNotEmpty ?? false
                ? result.title!.trim()
                : (DouyinUrlExtractor.extractShareText(rawInput) ?? rawInput));

      String? historyCover = (result.coverUrl?.trim().isNotEmpty ?? false)
          ? result.coverUrl!.trim()
          : null;
      if (historyCover == null) {
        for (final it in result.items) {
          if (it.type == MediaType.image && it.url.isNotEmpty) {
            historyCover = it.url;
            break;
          }
        }
      }

      final summaryTags = <String>[];
      if (result.videoCount > 0) {
        summaryTags.add(result.isImagePost ? '实况' : '视频');
      }
      if (result.imageCount > 0) summaryTags.add('图集');
      if (result.audioCount > 0) summaryTags.add('音频');
      summaryTags.add('文案');

      await HistoryStore.addRecord(
        HistoryItem(
          id: url,
          url: url,
          rawInput: rawInput,
          fullDesc: historyDesc,
          title: result.title,
          coverUrl: historyCover,
          isImagePost: result.isImagePost,
          mediaSummary: summaryTags.join('/'),
          itemCount: result.items.length,
          createdAt: DateTime.now(),
        ),
      );

      ctx.onRequestParseTab();
      final selection = await _chooseSingleWork(result, url);
      if (!ctx.mounted) return;
      if (selection == null) {
        ctx.sniffer.cancelActiveTask();
        ctx.logs.add('已取消保存');
        return;
      }
      final selected = selection.items;

      final candidateDesc = (result.desc?.trim().isNotEmpty ?? false)
          ? result.desc!.trim()
          : DouyinUrlExtractor.extractShareText(rawInput);

      ctx.logs.add('开始下载 ${selected.length} 个选中资源...');
      final baseName = FileNameFormatter.sanitize(
        FileNameFormatter.buildBaseName(candidateDesc),
      );
      final cancelToken = CancelToken();
      ctx.setDownloadCancelToken(cancelToken);
      DownloadCancelRegistry.attach(
        () => cancelToken.cancel('用户取消下载'),
      );
      final savedTypes = await ctx.downloader.downloadItems(
        selected,
        cookie: result.cookie,
        baseTitle: baseName,
        cancelToken: cancelToken,
        onProgress: ctx.updateBatchProgress,
      );
      if (!ctx.mounted) return;
      if (savedTypes.isNotEmpty) {
        HistoryStore.markSavedWithMeta(url, savedBaseName: baseName);
      }
      if (savedTypes.contains(MediaType.image)) {
        ctx.logs.add(
          '图片已保存到${SaveLocationStore.getDisplayPath(MediaType.image)}',
        );
      }
      if (savedTypes.contains(MediaType.video)) {
        ctx.logs.add(
          '视频已保存到${SaveLocationStore.getDisplayPath(MediaType.video)}',
        );
      }
      if (savedTypes.contains(MediaType.audio)) {
        ctx.logs.add(
          '音频已保存到${SaveLocationStore.getDisplayPath(MediaType.audio)}',
        );
      }
    } on DouyinDownloadCancelledException {
      if (ctx.mounted) ctx.logs.add('已取消保存');
    } on SniffCancelledException {
      if (ctx.mounted) ctx.logs.add('已取消解析');
    } catch (error) {
      if (!ctx.mounted) return;
      ctx.logs.add('操作失败：${ParseFlowHelper.friendlyError(error)}');
    } finally {
      DownloadCancelRegistry.detach();
      ctx.setDownloadCancelToken(null);
      if (ctx.mounted) {
        ctx.setParsing(false);
        ctx.busy.value = false;
        ctx.refresh();
      }
    }
  }

  Future<SelectedWork?> _chooseSingleWork(
    SingleWorkResult result,
    String url,
  ) async {
    final work = SaveWorkItem(
      url: url,
      kind: result.isImagePost ? WorkMediaKind.image : WorkMediaKind.video,
      title: result.displayTitle,
      coverUrl: result.coverUrl ?? '',
    );
    final session = SaveSelectionSession.singleWork(
      work: work,
      parsed: result,
      seed: TerminalMemoryStore.seed,
    );
    try {
      if (result.isImagePost) {
        final confirmed = await ImagePreviewSheet.show(
          ctx.context,
          session: session,
          workUrl: url,
          items: result.items,
          headers: ParseSaveCoordinator.mediaHeaders,
        );
        if (!ctx.mounted || confirmed != true) return null;
      } else {
        final picked = await ctx.saveCoordinator.pickSingleTier(
          ctx.context,
          session,
          url,
        );
        if (!ctx.mounted || !picked) return null;
      }
      return session.buildSelectedWork(url);
    } finally {
      SelectionDebugBridge.detach(session);
      session.close();
    }
  }
}
