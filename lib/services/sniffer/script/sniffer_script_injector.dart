import '../../script/douyin/douyin_sniff_script.dart';
import 'sniffer_script_host.dart';

/// 捕获脚本注入器：完整脚本每文档一次，轮询只触发页内 tick。
class SnifferScriptInjector {
  SnifferScriptInjector(this.host);

  final SnifferScriptHost host;

  /// 注入完整脚本；脚本在 nonce 不一致或 about: 页时自行返回
  Future<void> injectFull() async {
    if (host.isDisposed || !host.isTaskActive) return;
    try {
      await host.controller.runJavaScript(
        "window.__dyTaskNonce='${host.taskNonce}';\n$kDouyinSniffJs",
      );
      host.markScriptAccepted();
    } catch (e) {
      host.logInjectFailure(e.toString());
    }
  }

  /// 轻量 tick：脚本已就绪时只触发页内扫描，未就绪才重传完整脚本
  Future<void> tick() async {
    if (host.isDisposed || !host.isTaskActive) return;
    final nonce = host.taskNonce;
    try {
      final result = await host.controller.runJavaScriptReturningResult(
        "window.__dyTaskNonce='$nonce';"
        "(function(){var S=window.__dyState;"
        "if(window.__dySniffTick&&S&&S.nonce==='$nonce'){window.__dySniffTick();return true;}"
        "return false;})();",
      );
      if (result.toString() == 'true') {
        host.markScriptAccepted();
        return;
      }
    } catch (_) {
      // 页面尚未就绪或不是网页地址，回退到完整注入
    }
    await injectFull();
  }
}
