import 'dart:async';

import 'package:dio/dio.dart';

import '../../../../models/history_item.dart';
import '../../../../models/media_item.dart';
import '../../../../services/download/download_cancel_registry.dart';
import '../../../../services/media/video_downloader.dart';
import '../../../../services/selection/debug/selection_debug_bridge.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../../../services/sniffer/lifecycle/sniff_cancelled_exception.dart';
import '../../../../services/user_home/user_home_batch_saver.dart';
import '../../../../utils/history/history_store.dart';
import '../../../../utils/login_state_store.dart';
import '../../../../utils/memory/terminal_memory_store.dart';
import '../../../../utils/url_parser.dart';
import '../../../../widgets/save_page/middle_multi_work_sheet.dart';
import '../../../../widgets/save_page/top_multi_home_sheet.dart';
import '../common/parse_flow_context.dart';
import '../common/parse_flow_helper.dart';
import '../common/parse_save_coordinator.dart';

/// 作者主页批量解析协调器：主页抓取、首屏去重、写入历史、顶层选作者与批量下载
class HomeParseCoordinator {
  const HomeParseCoordinator(this.ctx);

  final ParseFlowContext ctx;

  Future<void> parseUserHomes(List<String> homeUrls) async {
    var isLogged = ctx.loggedIn.value;
    if (!isLogged) {
      try {
        isLogged = await LoginStateStore.isLoggedIn() &&
            await LoginStateStore.checkWebViewCookieSession();
        if (isLogged) ctx.loggedIn.value = true;
      } catch (_) {}
    }

    if (!isLogged) {
      ctx.logs.add('未登录模式：仅解析首屏作品');
    }

    final profiles = <UserHomeProfile>[];
    final worksBySecUid = <String, List<SaveWorkItem>>{};
    final seenHomeKeys = <String>{};
    final orderedHomeUrls = <String>[
      ...homeUrls.where(UrlParser.isUserHomeUrl),
      ...homeUrls.where((url) => !UrlParser.isUserHomeUrl(url)),
    ];

    try {
      for (var i = 0; i < orderedHomeUrls.length; i++) {
        if (!ctx.mounted || !ctx.isParsing()) return;
        final homeUrl = orderedHomeUrls[i];
        ctx.logs.add(
          '正在捕获主页作品 (${i + 1}/${orderedHomeUrls.length})...',
        );
        try {
          final homeResult =
              await ctx.sniffer.userHome.extractAllWorks(homeUrl);
          if (!ctx.mounted || !ctx.isParsing()) return;

          final secUid = homeResult.secUid.trim();
          if (secUid.isEmpty) {
            ctx.logs.add('第 ${i + 1} 个主页未识别到 secUid，已跳过');
            continue;
          }
          if (!seenHomeKeys.add(secUid)) {
            ctx.logs.add(
              '重复主页已去重（同一作者的口令与网址）: ${homeResult.nickname}',
            );
            continue;
          }

          if (homeResult.partial) {
            ctx.logs.add(
              '未登录仅获取首屏 ${homeResult.count} 条（主页标注 ${homeResult.worksTotalTag} 条），登录后可获取全部',
            );
          }

          final works = _buildHomeWorks(homeResult);
          if (works.isEmpty) {
            ctx.logs.add(
              '作者【${homeResult.nickname.isNotEmpty ? homeResult.nickname : "未知作者"}】暂无可保存作品，已跳过',
            );
            continue;
          }
          worksBySecUid[secUid] = works;
          await HistoryStore.addRecord(
            HistoryItem(
              id: 'home:$secUid',
              url: 'https://www.douyin.com/user/$secUid',
              rawInput: homeUrl,
              fullDesc: homeResult.nickname,
              title: homeResult.nickname,
              coverUrl: homeResult.avatarUrl,
              mediaSummary: '作者主页',
              itemCount: works.length,
              recordType: HistoryRecordType.userHome,
              authorSecUid: secUid,
            ),
          );
          profiles.add(homeResult.profile);
          final articleText = homeResult.filteredArticleCount > 0
              ? '，已过滤 ${homeResult.filteredArticleCount} 条文章'
              : '';
          ctx.logs.add(
            '作者【${homeResult.nickname.isNotEmpty ? homeResult.nickname : "未知作者"}】'
            '作品捕获完成：${works.length} 条可保存，'
            '已关联封面 ${homeResult.coversCount} 条$articleText',
          );
        } on SniffCancelledException {
          rethrow;
        } catch (e) {
          if (!ctx.mounted || !ctx.isParsing()) return;
          ctx.logs.add('第 ${i + 1} 个主页捕获失败：${ParseFlowHelper.friendlyError(e)}');
        }
      }

      ctx.setParsing(false);
      ctx.refresh();

      if (profiles.isEmpty) {
        ctx.logs.add('未捕获到有效作者信息，请检查主页链接或登录状态');
        return;
      }
      if (!ctx.context.mounted) return;

      ctx.logs.add(
        '成功捕获 ${profiles.length} 位作者信息，正在打开顶层保存页',
      );
      ctx.onRequestParseTab();

      final session = SaveSelectionSession.home(
        profiles: profiles,
        worksBySecUid: worksBySecUid,
        seed: TerminalMemoryStore.seed,
      );
      SelectionDebugBridge.attach(session);

      try {
        final confirmed = await MultiHomePreviewSheet.show(
          ctx.context,
          session: session,
          headers: ParseSaveCoordinator.mediaHeaders,
          onOpenAuthor: (secUid, index) => _openAuthorWorks(session, secUid),
        );
        if (!ctx.context.mounted) return;
        if (confirmed != true) {
          ctx.logs.add('已取消多主页保存');
          return;
        }

        final selectedAuthors = session.authors
            .where((author) => author.selection.isSelected)
            .toList();
        if (selectedAuthors.isEmpty) {
          ctx.logs.add('未选择任何作者');
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
        ctx.logs.add('正在准备保存 ${selectedAuthors.length} 位作者...');

        final prepared = await ctx.saveCoordinator.prepareByAuthor(
          session,
          selectedAuthors,
          isCancelled: () => cancelToken.isCancelled,
          onProgress: (nickname, current, total) => ctx.updateBatchSaveProgress(
            current,
            total,
            '正在准备保存：$nickname $current/$total',
          ),
        );
        if (!ctx.mounted) return;
        if (cancelToken.isCancelled) {
          throw const DouyinDownloadCancelledException();
        }

        final homeSaver = UserHomeBatchSaver(workSaver: ctx.workBatchSaver);
        ctx.logs.add(
          '开始保存 ${selectedAuthors.length} 位作者（${ParseFlowHelper.qualityLabel(qualityMode)}）...',
        );

        final result = await homeSaver.saveAuthors(
          authors: selectedAuthors.map((author) => author.profile).toList(),
          worksBySecUid: prepared,
          qualityMode: qualityMode,
          cancelToken: cancelToken,
          onProgress: ctx.updateBatchSaveProgress,
          onLog: (message) {
            if (ctx.mounted) ctx.logs.add(message);
          },
        );
        if (!ctx.mounted) return;

        await HistoryStore.markSavedBatch({
          for (final author in result.authors)
            if (author.success) 'home:${author.secUid}': null,
        });

        final successCount = result.authors.where((a) => a.success).length;
        ctx.logs.add(
          '主页批量保存完成：成功 $successCount/${result.authors.length} 位作者，共 ${result.totalSaved} 项资源',
        );
      } finally {
        SelectionDebugBridge.detach(session);
        session.close();
      }
    } on DouyinDownloadCancelledException {
      if (ctx.mounted) ctx.logs.add('已取消主页批量保存');
    } on SniffCancelledException {
      if (ctx.mounted) {
        final cancelToken = ctx.getDownloadCancelToken();
        ctx.logs.add(
          cancelToken?.isCancelled == true ? '已取消主页批量保存' : '已取消解析',
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ctx.logs.add('主页捕获失败：${ParseFlowHelper.friendlyError(e)}');
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

  void _openAuthorWorks(SaveSelectionSession session, String secUid) {
    final rows = session.rowsOf(secUid);
    if (!ctx.mounted || rows.isEmpty) return;
    unawaited(
      MiddleMultiWorkSheet.show(
        ctx.context,
        session: session,
        secUid: secUid,
        headers: ParseSaveCoordinator.mediaHeaders,
        nested: true,
        onOpenWork: (workUrl, index) =>
            ctx.saveCoordinator.openWorkDetail(ctx.context, session, workUrl),
      ).then((confirmed) {
        if (!ctx.mounted) return;
        if (confirmed == true) {
          ctx.logs.add(
            '作者作品已更新：${session.selectedCountOf(rows)}/${rows.length}',
          );
        }
      }),
    );
  }

  List<SaveWorkItem> _buildHomeWorks(UserHomeResult result) {
    final works = <SaveWorkItem>[];
    for (final url in result.workUrls) {
      if (UrlParser.isArticleUrl(url)) continue;
      final kind = UrlParser.classifyWorkPage(url) == DouyinWorkPage.note
          ? WorkMediaKind.image
          : WorkMediaKind.video;
      works.add(
        SaveWorkItem(
          url: url,
          kind: kind,
          title: result.getTitle(url) ?? '',
          coverUrl: result.getCover(url) ?? '',
        ),
      );
    }
    return works;
  }
}
