part of '../../page/parse_page.dart';

/// 解析页骨架：输入、状态与保存入口。
extension _ParsePageFrame on _ParsePageState {
  Widget _buildParsePage(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Expanded(
          child: ValueListenableBuilder<bool>(
            valueListenable: widget.busy,
            builder: (context, busy, _) {
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  SizedBox(
                    height: 120,
                    child: Stack(
                      children: [
                        NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification.depth == 0) {
                              _handleScrollNotification(notification);
                            }
                            return false;
                          },
                          child: TextField(
                            controller: _inputController,
                            scrollController: _inputScrollController,
                            maxLines: null,
                            expands: true,
                            textAlignVertical: TextAlignVertical.top,
                            decoration: const InputDecoration(
                              labelText: '抖音分享口令 / 链接',
                              hintText:
                                  '粘贴分享口令或链接，例如 https://v.douyin.com/xxxx/',
                              border: OutlineInputBorder(),
                              alignLabelWithHint: true,
                            ),
                          ),
                        ),
                        // 悬浮定制滑动指示器：无手势劫持、向左微调防遮挡边框、不滑动渐隐
                        Positioned(
                          top: 8.0 + (_scrollProgress * (104.0 - _thumbHeight)),
                          right: 7.0,
                          child: IgnorePointer(
                            child: AnimatedOpacity(
                              opacity: _showScrollIndicator ? 1.0 : 0.0,
                              duration: const Duration(milliseconds: 250),
                              child: Container(
                                width: 3.0,
                                height: _thumbHeight,
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primary.withValues(
                                    alpha: 0.65,
                                  ),
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      FilledButton.tonalIcon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.paste_rounded, size: 18),
                        label: const Text('粘贴'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: busy ? null : _startParse,
                          icon: const Icon(Icons.download),
                          label: Text(busy ? '处理中...' : '解析作品'),
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                      if (_isParsing) ...[
                        const SizedBox(width: 8),
                        IconButton.filledTonal(
                          onPressed: _cancelParse,
                          icon: const Icon(Icons.close_rounded, size: 20),
                          tooltip: '终止解析',
                          style: IconButton.styleFrom(
                            shape: const CircleBorder(),
                            minimumSize: const Size(48, 48),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 16),
                  ValueListenableBuilder<double?>(
                    valueListenable: _downloadProgress,
                    builder: (context, progress, _) {
                      return LinearProgressIndicator(
                        value: busy ? progress : 0,
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                  StatusCard(logs: widget.logs),
                  const SizedBox(height: 12),
                  _LoginPromptBanner(
                    loggedIn: widget.loggedIn,
                    onTapLogin: widget.onTapAccount,
                  ),
                  const SizedBox(height: 16),
                ],
              );
            },
          ),
        ),
        // 页面底部标识文字（仅展示，不可点击）
        Padding(
          padding: const EdgeInsets.only(top: 8, bottom: 10),
          child: Text(
            '本地、解析、隐私',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
          ),
        ),
      ],
    );
  }
}
