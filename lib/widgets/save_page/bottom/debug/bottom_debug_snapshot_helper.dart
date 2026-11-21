import 'package:flutter/foundation.dart';

import '../../../../services/selection/debug/selection_snapshot.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../../../utils/debug/save_page_debug_store.dart';

/// 底层保存页调试快照同步辅助
abstract final class BottomDebugSnapshotHelper {
  /// 发布底层快照（仅在调试模式）
  static void publish(SaveSelectionSession session, String workUrl) {
    if (!kDebugMode) return;
    SavePageDebugStore.update(
      'bottom',
      SelectionSnapshot.bottom(session, workUrl),
    );
  }
}
