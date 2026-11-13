import 'package:flutter/material.dart';

import '../utils/download_settings_store.dart';
import '../utils/save_location_store.dart';
import '../widgets/save_location_dialog.dart';

/// 下载与更新二级设置页面：合并管理保存位置、视频画质偏好与自动更新检查
class DownloadSettingsPage extends StatelessWidget {
  const DownloadSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('下载与更新'),
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
                      ? '单作品与主页链接均为默认路径'
                      : '已自定义单作品或主页保存路径',
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
                  '保存页同一分辨率只展示最高画质的下载选项',
                ),
                value: onlyHighest,
                onChanged: (val) {
                  DownloadSettingsStore.setOnlyHighestQualityPerResolution(val);
                },
              );
            },
          ),
          const Divider(height: 1),

          // 3. 自动检查更新开关
          ValueListenableBuilder<bool>(
            valueListenable: DownloadSettingsStore.autoCheckUpdateNotifier,
            builder: (context, autoCheck, _) {
              return SwitchListTile(
                secondary: const Icon(Icons.update_rounded),
                title: const Text('自动检查更新'),
                subtitle: const Text(
                  '打开软件等候 2 秒后自动检测最新版本',
                ),
                value: autoCheck,
                onChanged: (val) {
                  DownloadSettingsStore.setAutoCheckUpdate(val);
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
