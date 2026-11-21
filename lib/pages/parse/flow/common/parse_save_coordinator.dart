import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../models/save_page/selection/author_selection_view.dart';
import '../../../../models/save_page/selection/selected_work.dart';
import '../../../../models/save_page/work_open_exception.dart';
import '../../../../models/single_work/media_download_item.dart';
import '../../../../services/multi_work/article_work_exception.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../../../services/selection/session_work_preparer.dart';
import '../../../../services/sniffer/facade/douyin_sniffer.dart';
import '../../../../utils/app_stores.dart';
import '../../../../utils/debug/log_controller.dart';
import '../../../../utils/settings/video_quality_utils.dart';
import '../../../../widgets/save_page/bottom/widget/video_tier_picker_sheet.dart';
import '../../../../widgets/save_page/bottom_media_sheet.dart';
import 'parse_flow_helper.dart';

/// 保存页流程协调器：管理图文资源网格、画质档位选择与按作者补解析解算
class ParseSaveCoordinator {
  const ParseSaveCoordinator({
    required this.sniffer,
    required this.logs,
    this.stores,
  });

  final DouyinSniffer sniffer;
  final LogController logs;
  final AppStores? stores;

  /// 加载封面/头像所需的统一请求头
  static const Map<String, String> mediaHeaders = {
    'User-Agent': DouyinSniffer.desktopUserAgent,
    'Referer': 'https://www.douyin.com/',
  };

  /// 进入 resource 层：只等待解析准备，子页面压栈后立即返回
  Future<void> openWorkDetail(
    BuildContext context,
    SaveSelectionSession session,
    String workUrl,
  ) async {
    final row = session.workOf(workUrl);
    if (row == null) return;

    if (!row.parsed) {
      final title = row.work.title.trim().isNotEmpty
          ? row.work.title.trim()
          : workUrl;
      logs.add('正在解析作品：$title');
      try {
        final parsed = await sniffer.sniffVideoUrl(workUrl);
        if (!context.mounted) return;
        session.ingest(workUrl, parsed);
      } on ArticleWorkException catch (e) {
        final msg = '已过滤文章作品：${e.message}';
        if (context.mounted) logs.add(msg);
        throw WorkOpenException(msg);
      } catch (e) {
        final msg = '作品解析失败：${ParseFlowHelper.friendlyError(e)}';
        if (context.mounted) {
          logs.add(msg);
        }
        throw WorkOpenException(msg);
      }
    }
    if (!context.mounted) return;

    final parsed = session.workOf(workUrl)?.work.parsedResult;
    if (parsed == null || parsed.items.isEmpty) {
      const msg = '该作品未捕获到可下载资源';
      logs.add(msg);
      throw const WorkOpenException(msg);
    }
    if (row.behavesAsVideo) {
      presentWorkTier(context, session, workUrl);
      return;
    }
    presentWorkMedia(context, session, workUrl, parsed.items);
  }

  /// 主页/多作品：视频档位面板压栈后立即返回
  void presentWorkTier(
    BuildContext context,
    SaveSelectionSession session,
    String workUrl,
  ) {
    final row = session.workOf(workUrl);
    if (row == null || !row.behavesAsVideo) return;
    final tiers = VideoQualityUtils.displayTiers(
      row.tiers,
      onlyHighestPerResolution:
          stores?.downloadSettings.onlyHighestQualityPerResolution ?? true,
    );
    if (tiers.isEmpty) return;

    unawaited(
      VideoTierPickerSheet.show(
        context,
        session: session,
        workUrl: workUrl,
        tiers: tiers,
        nested: true,
      ).then((_) {
        if (!context.mounted) return;
        final tier = session.workOf(workUrl)?.selectedTier;
        if (tier == null) return;
        logs.add(
          '当前画质：${tierLabel(tier)}（${tier.formattedSize}）',
        );
      }),
    );
  }

  /// 图文作品：资源网格压栈后立即返回
  void presentWorkMedia(
    BuildContext context,
    SaveSelectionSession session,
    String workUrl,
    List<MediaItem> items,
  ) {
    unawaited(
      ImagePreviewSheet.show(
        context,
        session: session,
        workUrl: workUrl,
        items: items,
        headers: mediaHeaders,
        nested: true,
        debugStore: stores?.savePageDebug,
      ).then((_) {
        if (!context.mounted) return;
        final selected = session.selectedResourceCount(workUrl);
        logs.add('已选择 $selected/${items.length} 个资源');
      }),
    );
  }

  /// 单作品视频：底部按钮即确认，返回 true 表示用户完成选择
  Future<bool> pickSingleTier(
    BuildContext context,
    SaveSelectionSession session,
    String workUrl,
  ) async {
    final row = session.workOf(workUrl);
    if (row == null || !row.behavesAsVideo) return false;
    final tiers = VideoQualityUtils.displayTiers(
      row.tiers,
      onlyHighestPerResolution:
          stores?.downloadSettings.onlyHighestQualityPerResolution ?? true,
    );
    if (tiers.isEmpty) return false;

    final confirmed = await VideoTierPickerSheet.show(
      context,
      session: session,
      workUrl: workUrl,
      tiers: tiers,
    );
    if (!context.mounted || confirmed != true) return false;

    final tier = session.workOf(workUrl)?.selectedTier;
    if (tier != null) {
      logs.add(
        '已选择 ${tierLabel(tier)}（${tier.formattedSize}）',
      );
    }
    return true;
  }

  static String tierLabel(MediaItem tier) {
    if (tier.resolutionLabel.isNotEmpty) return tier.resolutionLabel;
    return tier.resolution ?? tier.gearName ?? '默认画质';
  }

  /// 按作者补解析并解算为可落盘对象
  Future<Map<String, List<SelectedWork>>> prepareByAuthor(
    SaveSelectionSession session,
    Iterable<AuthorSelectionView> authors, {
    bool Function()? isCancelled,
    void Function(String nickname, int current, int total)? onProgress,
  }) async {
    final result = <String, List<SelectedWork>>{};
    for (final author in authors) {
      if (isCancelled?.call() ?? false) break;
      final urls = session.workUrlsOf(author.secUid);
      final nickname = author.profile.nickname.trim().isNotEmpty
          ? author.profile.nickname.trim()
          : '未知作者';
      result[author.secUid] = await SessionWorkPreparer.prepare(
        session,
        urls,
        sniffer.sniffVideoUrl,
        isCancelled: isCancelled,
        onProgress: (current, total, label) =>
            onProgress?.call(nickname, current, total),
      );
      if (isCancelled?.call() ?? false) break;
    }
    return result;
  }
}
