import 'package:flutter/material.dart';

import '../utils/download_settings_store.dart';
import '../utils/save_location_store.dart';
import '../widgets/save_location_dialog.dart';

/// 下载设置二级页面：合并管理保存位置与视频画质偏好
class DownloadSettingsPage extends StatelessWidget {
  const DownloadSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载设置'),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // 1. 自定义保存位置
          ValueListenableBuilder<SaveLocationConfig>(
            valueListenable: SaveLocationStore.notifier,
            builder: (context, _, _) {
              final isDefault = SaveLocationStore.isAllDefault;
              return ListTile(
                leading: const Icon(Icons.folder_open_outlined),
                title: const Text('自定义保存位置'),
                subtitle: Text(
                  isDefault
                      ? '默认相册路径（/Movies、/Pictures、/Music）'
                      : '已自定义部分或全部目录',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => SaveLocationDialog.show(context),
              );
            },
          ),
          const Divider(height: 1),

          // 2. 仅显示同分辨率下最高画质开关
          ValueListenableBuilder<bool>(
            valueListenable: DownloadSettingsStore.onlyHighestQualityNotifier,
            builder: (context, onlyHighest, _) {
              return SwitchListTile(
                secondary: const Icon(Icons.high_quality_outlined),
                title: const Text('仅显示同分辨率下最高画质'),
                subtitle: const Text(
                  '开启后，同一分辨率（如 1080P）只展示最高码率的最优档位；关闭则列出全部检测到的画质档位',
                ),
                value: onlyHighest,
                onChanged: (val) {
                  DownloadSettingsStore.setOnlyHighestQualityPerResolution(val);
                },
              );
            },
          ),
          const Divider(height: 1),
        ],
      ),
    );
  }
}
