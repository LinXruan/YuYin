import 'package:flutter/foundation.dart';

import '../../../../services/selection/debug/selection_snapshot.dart';
import '../../../../services/selection/save_selection_session.dart';
import '../../../../utils/debug/save_page_debug_store.dart';

/// 顶层保存页调试快照辅助器
abstract final class TopDebugSnapshotHelper {
  static void publish(
    SaveSelectionSession session, {
    SavePageDebugStore? debugStore,
  }) {
    if (!kDebugMode || debugStore == null) return;
    debugStore.update(
      'top',
      SelectionSnapshot.top(session),
    );
  }
}
