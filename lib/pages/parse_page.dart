import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/media_item.dart';
import '../services/douyin_sniffer.dart';
import '../services/video_downloader.dart';
import '../utils/log_controller.dart';
import '../utils/url_parser.dart';
import '../widgets/image_preview_sheet.dart';
import '../widgets/video_quality_sheet.dart';

/// 解析页：粘贴链接 -> 嗅探 -> 选择画质/图片 -> 下载到相册
class ParsePage extends StatefulWidget {
  const ParsePage({
    super.key,
    required this.sniffer,
    required this.downloader,
    required this.logs,
    required this.busy,
    required this.onRequestParseTab,
  });

  final DouyinSniffer sniffer;
  final VideoDownloader downloader;
  final LogController logs;
  final ValueNotifier<bool> busy;
  final VoidCallback onRequestParseTab;

  @override
  State<ParsePage> createState() => _ParsePageState();
}

class _ParsePageState extends State<ParsePage> {
  final TextEditingController _inputController = TextEditingController();
  double? _progress;
  String _lastProgressKey = '';

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  /// 一键粘贴剪贴板内容
  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && mounted) {
      _inputController.text = data!.text!;
    }
  }

  /// 主流程：提取短链 -> 嗅探 -> 选择资源 -> 下载选中项
  Future<void> _startParse() async {
    if (widget.busy.value) return;
    FocusScope.of(context).unfocus();

    widget.logs.reset('正在提取短链...');
    setState(() {
      _progress = null;
      _lastProgressKey = '';
    });
    widget.busy.value = true;

    final url = UrlParser.extractDouyinUrl(_inputController.text);
    if (url == null) {
      widget.logs.add('未识别到有效的抖音链接，请检查粘贴内容');
      widget.busy.value = false;
      return;
    }

    try {
      widget.logs.add('正在解析作品...');
      final result = await widget.sniffer.sniffVideoUrl(url);
      if (!mounted) return;
      if (result.items.isEmpty) {
        widget.logs.add('未解析到可下载资源，请检查链接或稍后重试');
        return;
      }

      // 用户可能已切到其他 Tab，先切回解析页再弹选择面板
      widget.onRequestParseTab();
      final selected = await _chooseItems(result);
      if (!mounted) return;
      if (selected == null || selected.isEmpty) {
        // 取消后立即停止后台嗅探和网页加载，避免日志继续刷
        widget.sniffer.cancelActiveTask();
        widget.logs.add('已取消下载');
        return;
      }

      widget.logs.add('开始下载 ${selected.length} 个选中资源...');
      await widget.downloader.downloadItems(
        selected,
        cookie: result.cookie,
        onProgress: _updateBatchProgress,
      );
      widget.logs.add(
        selected.length == 1
            ? '已保存到相册！'
            : '全部 ${selected.length} 个资源已无水印保存至系统相册！',
      );
    } catch (error) {
      widget.logs.add('操作失败：${_friendlyError(error)}');
    } finally {
      if (mounted) {
        widget.busy.value = false;
        setState(() => _progress = null);
      }
    }
  }

  /// 根据作品类型弹出对应选择面板，返回用户选中的资源
  Future<List<MediaItem>?> _chooseItems(SniffResult result) async {
    if (result.isImagePost) {
      // 图文/实况图集：网格预览并勾选
      return ImagePreviewSheet.show(
        context,
        items: result.items,
        headers: const {
          'User-Agent': DouyinSniffer.desktopUserAgent,
          'Referer': 'https://www.douyin.com/',
        },
      );
    }

    // 普通视频：从全部清晰度档位中选择一个
    final picked = await VideoQualitySheet.show(context, result.items);
    if (picked == null) return null;
    final quality = picked.resolutionLabel.isNotEmpty
        ? picked.resolutionLabel
        : (picked.resolution ?? picked.gearName ?? '默认画质');
    widget.logs.add('已选择 $quality（${picked.formattedSize}）');
    return [picked];
  }

  /// 刷新批量下载进度（同一行内更新，避免刷屏）
  void _updateBatchProgress(int current, int total, double itemProgress) {
    final percent = (itemProgress * 100).round();
    final key = '$current/$total/$percent';
    if (!mounted || key == _lastProgressKey) return;
    _lastProgressKey = key;

    // 总进度 = 已完成项 + 当前项进度
    final overall = total == 0 ? 0.0 : ((current - 1) + itemProgress) / total;
    widget.logs.upsertLast(
      '正在下载第',
      '正在下载第 $current/$total 个资源（$percent%）...',
    );
    setState(() {
      _progress = overall.clamp(0.0, 1.0).toDouble();
    });
  }

  /// 把异常转换成简短的中文提示
  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      final message = error.message;
      if (message != null && message.isNotEmpty) return message;
      return '嗅探超时，请检查链接是否有效后重试';
    }
    if (error is DioException && error.response?.statusCode == 403) {
      return '视频服务器拒绝了请求（403），请稍后重试';
    }
    return error.toString().replaceFirst(RegExp(r'^(Exception|Bad state): '), '');
  }

  @override
  Widget build(BuildContext context) {
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
                  TextField(
                    controller: _inputController,
                    minLines: 3,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: '抖音分享口令 / 链接',
                      hintText:
                          '粘贴分享口令或链接，例如 https://v.douyin.com/xxxx/',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      TextButton(
                        onPressed: busy ? null : _pasteFromClipboard,
                        child: const Text('粘贴'),
                      ),
                      TextButton(
                        onPressed: busy ? null : _inputController.clear,
                        child: const Text('清空'),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    onPressed: busy ? null : _startParse,
                    icon: const Icon(Icons.download),
                    label: Text(busy ? '处理中...' : '解析作品'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                  const SizedBox(height: 16),
                  LinearProgressIndicator(value: busy ? _progress : 0),
                  const SizedBox(height: 16),
                  _StatusCard(logs: widget.logs),
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
              color: Colors.grey.shade600,
            ),
          ),
        ),
      ],
    );
  }
}

/// 解析页底部的当前状态卡片：只显示最新一条日志
class _StatusCard extends StatelessWidget {
  const _StatusCard({required this.logs});

  final LogController logs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<List<String>>(
      valueListenable: logs,
      builder: (context, value, _) {
        final status = value.isEmpty
            ? '就绪：粘贴抖音链接后点击“解析作品”'
            : value.last;
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline,
                size: 18,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  status,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(height: 1.5),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
