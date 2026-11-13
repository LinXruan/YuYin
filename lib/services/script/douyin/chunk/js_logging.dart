/// 通道日志回传
const String jsLogging = r'''  }
  function log(msg) {
    if (S.logs[msg]) return; S.logs[msg] = true;
    try { window.DouyinChannel && window.DouyinChannel.postMessage(JSON.stringify({ type: 'log', msg: msg })); } catch (e) {}
  }
''';
