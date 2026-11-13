import '../models/media_item.dart';
import 'video_quality_utils.dart';

/// 三层保存页的纯选择树操作：上层控制下层，下层状态派生上层状态。
class SaveSelectionTree {
  SaveSelectionTree._();

  /// 作品状态：视频作品由底层返回的 state 决定；图文/实况按资源数量派生。
  static WorkSelectionState deriveWorkState(SaveWorkItem work) {
    if (work.isVideo) return work.selectionState;
    if (work.selectionState == WorkSelectionState.none &&
        work.selectedResources.isEmpty) {
      return WorkSelectionState.none;
    }
    if (work.selectedResources.isEmpty) {
      return work.selectionState;
    }

    final items = work.parsedResult?.items ?? const <MediaItem>[];
    if (items.isEmpty) return work.selectionState;

    final selectedUrls =
        work.selectedResources.map((item) => item.url).toSet();
    if (selectedUrls.isEmpty) return WorkSelectionState.none;
    if (selectedUrls.length >= items.length) {
      return WorkSelectionState.all;
    }
    return WorkSelectionState.partial;
  }

  /// 作者状态：由该作者全部作品派生。
  static AuthorSelectionState deriveAuthorState(List<SaveWorkItem> works) {
    if (works.isEmpty) return AuthorSelectionState.none;
    if (works.every((work) => work.selectionState.isAll)) {
      return AuthorSelectionState.all;
    }
    if (works.every((work) => !work.selectionState.isSelected)) {
      return AuthorSelectionState.none;
    }
    return AuthorSelectionState.partial;
  }

  /// 上层控制下层：作者全选/全不选，递归设置其全部作品。
  static List<SaveWorkItem> applyAuthorSelection(
    List<SaveWorkItem> works,
    AuthorSelectionState state,
  ) {
    if (state == AuthorSelectionState.partial) return works;
    final target = state == AuthorSelectionState.all
        ? WorkSelectionState.all
        : WorkSelectionState.none;
    return works
        .map((work) => applyWorkSelection(work, target))
        .toList();
  }

  /// 上层控制下层：作品全选/全不选，清空资源级选择；
  /// 空 selectedResources 在保存器中表示「全部资源」。
  static SaveWorkItem applyWorkSelection(
    SaveWorkItem work,
    WorkSelectionState state,
  ) {
    if (state == WorkSelectionState.partial) return work;
    return work.copyWith(
      selectionState: state,
      selectedResources: const [],
    );
  }

  /// 上层控制下层：按作品类型批量全选/全不选。
  static List<SaveWorkItem> applyCategorySelection(
    List<SaveWorkItem> works,
    WorkMediaKind kind,
    WorkSelectionState state,
  ) {
    if (state == WorkSelectionState.partial) return works;
    return works.map((work) {
      if (work.kind != kind) return work;
      return applyWorkSelection(work, state);
    }).toList();
  }

  /// 下层控制上层：底层返回后更新作品状态与资源。
  static SaveWorkItem applyBottomSelection(
    SaveWorkItem work,
    List<MediaItem> selectedResources,
    SingleWorkResult? parsedResult,
  ) {
    final parsed = parsedResult ?? work.parsedResult;
    final WorkSelectionState state;
    if (work.isVideo) {
      state = selectedResources.isEmpty
          ? WorkSelectionState.none
          : WorkSelectionState.all;
    } else {
      state = _deriveFromResources(
        parsed?.items ?? const [],
        selectedResources,
      );
    }

    return work.copyWith(
      selectionState: state,
      selectedResources: selectedResources,
      parsedResult: parsed,
    );
  }

  static WorkSelectionState _deriveFromResources(
    List<MediaItem> allItems,
    List<MediaItem> selectedResources,
  ) {
    if (selectedResources.isEmpty) return WorkSelectionState.none;
    if (allItems.isEmpty) return WorkSelectionState.all;
    final selectedUrls =
        selectedResources.map((item) => item.url).toSet();
    if (selectedUrls.length >= allItems.length) {
      return WorkSelectionState.all;
    }
    return WorkSelectionState.partial;
  }

  /// 画质聚合：全部最高 -> highest；全部最低 -> lowest；其余 -> mixed。
  static BatchVideoQualityMode? aggregateQuality(List<SaveWorkItem> works) {
    final choices = [
      for (final work in works)
        if (work.isVideo) work.qualityChoice,
    ];
    if (choices.isEmpty) return null;
    if (choices.every(
      (choice) => choice.level == WorkVideoQualityLevel.highest,
    )) {
      return BatchVideoQualityMode.highest;
    }
    if (choices.every(
      (choice) => choice.level == WorkVideoQualityLevel.lowest,
    )) {
      return BatchVideoQualityMode.lowest;
    }
    return BatchVideoQualityMode.mixed;
  }

  /// 上层画质控制：批量设置视频作品为最高/最低，并清空旧视频资源选择。
  static List<SaveWorkItem> applyQualityToWorks(
    List<SaveWorkItem> works,
    BatchVideoQualityMode mode,
  ) {
    if (mode == BatchVideoQualityMode.mixed) return works;
    final choice = mode == BatchVideoQualityMode.lowest
        ? const WorkVideoQualityChoice.lowest()
        : const WorkVideoQualityChoice.highest();
    return works.map((work) {
      if (!work.isVideo) return work;
      final resources = work.selectedResources
          .where((item) => item.type != MediaType.video)
          .toList();
      return work.copyWith(
        qualityChoice: choice,
        selectedResources: resources,
      );
    }).toList();
  }

  /// 上层画质控制：只作用于指定分类。
  static List<SaveWorkItem> applyQualityToCategory(
    List<SaveWorkItem> works,
    WorkMediaKind kind,
    BatchVideoQualityMode mode,
  ) {
    if (mode == BatchVideoQualityMode.mixed) return works;
    final choice = mode == BatchVideoQualityMode.lowest
        ? const WorkVideoQualityChoice.lowest()
        : const WorkVideoQualityChoice.highest();
    return works.map((work) {
      if (work.kind != kind) return work;
      final resources = work.selectedResources
          .where((item) => item.type != MediaType.video)
          .toList();
      return work.copyWith(
        qualityChoice: choice,
        selectedResources: resources,
      );
    }).toList();
  }

  /// 保存时解析单个作品的画质：
  /// 视频显式选择 > specific > mixed(尊重作品既有) > 批量最高/最低。
  static WorkVideoQualityChoice resolveWorkQuality(
    SaveWorkItem work,
    BatchVideoQualityMode mode,
  ) {
    for (final item in work.selectedResources) {
      if (item.type != MediaType.video) continue;
      final tiers = work.parsedResult?.videoItems ?? const <MediaItem>[];
      if (tiers.isNotEmpty) {
        return VideoQualityUtils.classifyChoice(tiers, item);
      }
      return WorkVideoQualityChoice.specific(item);
    }

    if (work.qualityChoice.level == WorkVideoQualityLevel.specific) {
      return work.qualityChoice;
    }
    if (mode == BatchVideoQualityMode.mixed) {
      return work.qualityChoice;
    }
    return mode == BatchVideoQualityMode.lowest
        ? const WorkVideoQualityChoice.lowest()
        : const WorkVideoQualityChoice.highest();
  }
}
