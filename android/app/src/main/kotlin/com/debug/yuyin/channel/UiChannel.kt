package com.debug.yuyin.channel

import android.app.Activity
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.view.Display
import com.debug.yuyin.R
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// 主题、外部跳转与显示信息的轻量通道。
class UiChannel(private val activity: Activity) {
    fun attach(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, CHANNEL_THEME).setMethodCallHandler { call, result ->
            when (call.method) {
                "setThemeMode" -> {
                    applyThemeMode(call.argument<String>("mode") ?: "system")
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, CHANNEL_APP).setMethodCallHandler { call, result ->
            when (call.method) {
                "openUrl" -> result.success(openUrl(call.argument<String>("url")))
                else -> result.notImplemented()
            }
        }
        MethodChannel(messenger, CHANNEL_DISPLAY).setMethodCallHandler { call, result ->
            when (call.method) {
                "getDisplayInfo" -> result.success(displayInfo())
                else -> result.notImplemented()
            }
        }
    }

    /// 冷启动最早期读取主题标记，确保启动背景与上次一致
    fun applySavedThemeMode() {
        try {
            val file = File(activity.filesDir, "theme_mode.flag")
            if (file.exists()) {
                applyThemeMode(file.readText().trim())
            }
        } catch (_: Exception) {
        }
    }

    fun applyThemeMode(mode: String) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val manager = activity.getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            manager?.let {
                val target = when (mode.lowercase()) {
                    "dark" -> UiModeManager.MODE_NIGHT_YES
                    "light" -> UiModeManager.MODE_NIGHT_NO
                    else -> UiModeManager.MODE_NIGHT_AUTO
                }
                it.setApplicationNightMode(target)
            }
        }
        val backgroundRes = when (mode.lowercase()) {
            "dark" -> R.drawable.launch_background_dark
            "light" -> R.drawable.launch_background_light
            else -> R.drawable.launch_background
        }
        activity.window.setBackgroundDrawableResource(backgroundRes)
    }

    fun enableAdaptiveHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return
        try {
            val display = targetDisplay() ?: return
            val currentMode = display.mode
            val sameSize = display.supportedModes.filter {
                it.physicalWidth == currentMode.physicalWidth &&
                    it.physicalHeight == currentMode.physicalHeight
            }
            val candidates = if (sameSize.isNotEmpty()) {
                sameSize
            } else {
                display.supportedModes.toList()
            }
            val best = candidates.maxByOrNull { it.refreshRate } ?: return
            val params = activity.window.attributes
            params.preferredDisplayModeId = best.modeId
            activity.window.attributes = params
        } catch (_: Exception) {
        }
    }

    private fun displayInfo(): Map<String, Any> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val display = targetDisplay()
                if (display != null) {
                    val mode = display.mode
                    return mapOf(
                        "activeRefreshRate" to mode.refreshRate.toDouble(),
                        "width" to mode.physicalWidth,
                        "height" to mode.physicalHeight,
                        "maxRefreshRate" to
                            (display.supportedModes.maxOfOrNull { it.refreshRate }
                                ?: mode.refreshRate).toDouble(),
                        "supportedModesCount" to display.supportedModes.size
                    )
                }
            } catch (_: Exception) {
            }
        }
        return mapOf(
            "activeRefreshRate" to 60.0,
            "maxRefreshRate" to 60.0,
            "width" to 0,
            "height" to 0,
            "supportedModesCount" to 1
        )
    }

    private fun targetDisplay(): Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            activity.display
        } else {
            @Suppress("DEPRECATION")
            activity.windowManager.defaultDisplay
        }
    }

    private fun openUrl(url: String?): Boolean {
        if (url.isNullOrBlank()) return false
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            activity.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private companion object {
        const val CHANNEL_THEME = "com.debug.yuyin/theme"
        const val CHANNEL_APP = "com.debug.yuyin/app"
        const val CHANNEL_DISPLAY = "com.debug.yuyin/display_mode"
    }
}