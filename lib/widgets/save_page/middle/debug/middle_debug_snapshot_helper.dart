import 'package:flutter/foundation.dart';

import '../../../../services/selection/debug/selection_snapshot.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../../../utils/debug/save_page_debug_store.dart';

/// 中层保存页调试快照辅助器
abstract final class MiddleDebugSnapshotHelper {
  static void publish(SaveSelectionSession session, String secUid) {
    if (!kDebugMode) return;
    SavePageDebugStore.update(
      'middle',
      SelectionSnapshot.middle(session, secUid),
    );
  }
}
