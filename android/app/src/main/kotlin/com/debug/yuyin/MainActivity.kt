package com.debug.yuyin

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.debug.yuyin.audio.AudioPreviewPlayer
import com.debug.yuyin.channel.StorageChannel
import com.debug.yuyin.channel.UiChannel
import com.debug.yuyin.install.InstallerChannel

/// 应用入口：只负责组装各通道与生命周期分发。
class MainActivity : FlutterActivity() {
    private lateinit var uiChannel: UiChannel
    private lateinit var storageChannel: StorageChannel
    private var installerChannel: InstallerChannel? = null
    private var audioPreviewPlayer: AudioPreviewPlayer? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        uiChannel = UiChannel(this)
        storageChannel = StorageChannel(this)
        // 在最早期读取并设置启动背景与自适应高刷新率，确保冷启动无缝匹配最高硬件刷新率
        uiChannel.applySavedThemeMode()
        uiChannel.enableAdaptiveHighRefreshRate()
        super.onCreate(savedInstanceState)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            uiChannel.enableAdaptiveHighRefreshRate()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        uiChannel.attach(flutterEngine)
        installerChannel = InstallerChannel(this).also { it.attach(flutterEngine) }
        storageChannel.attach(flutterEngine)
        audioPreviewPlayer = AudioPreviewPlayer(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, AUDIO_CHANNEL)
        )
    }

    override fun onStop() {
        // 退到后台时暂停试听，避免无交互继续播放
        audioPreviewPlayer?.pauseForBackground()
        super.onStop()
    }

    override fun onDestroy() {
        audioPreviewPlayer?.release()
        audioPreviewPlayer = null
        storageChannel.release()
        installerChannel?.release()
        installerChannel = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        // 若从安装未知应用权限设置页返回且已有暂存安装包，自动续装不断流
        installerChannel?.resumePendingInstall()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (installerChannel?.onActivityResult(requestCode) == true) return
        storageChannel.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        storageChannel.onRequestPermissionsResult(requestCode, grantResults)
    }

    private companion object {
        const val AUDIO_CHANNEL = "com.debug.yuyin/audio_player"
    }
}
