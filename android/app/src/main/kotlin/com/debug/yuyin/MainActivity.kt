package com.debug.yuyin

import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val themeChannel = "com.debug.yuyin/theme"
    private val appChannel = "com.debug.yuyin/app"

    override fun onCreate(savedInstanceState: Bundle?) {
        // 在最早期读取并设置启动背景与应用夜间模式，确保 cold start 启动画面无缝匹配用户选择
        applySavedThemeMode()
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, themeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setThemeMode" -> {
                        val mode = call.argument<String>("mode") ?: "system"
                        applyThemeMode(mode)
                        result.success(true)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, appChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "openUrl" -> {
                        val url = call.argument<String>("url")
                        if (!url.isNullOrBlank()) {
                            try {
                                val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url))
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                                result.success(true)
                            } catch (e: Exception) {
                                result.error("OPEN_FAILED", e.message, null)
                            }
                        } else {
                            result.error("INVALID_URL", "URL is empty", null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun applySavedThemeMode() {
        try {
            val file = File(filesDir, "theme_mode.flag")
            if (file.exists()) {
                val mode = file.readText().trim()
                applyThemeMode(mode)
            }
        } catch (_: Exception) {
        }
    }

    private fun applyThemeMode(mode: String) {
        // 1. Android 12+ (API 31+): 系统级应用夜间模式持久化
        // Android 系统会自动记住该包名的夜间模式，下次冷启动由系统启动窗口(SplashScreen)精准呈现
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val uiModeManager = getSystemService(Context.UI_MODE_SERVICE) as? UiModeManager
            uiModeManager?.let {
                val targetMode = when (mode.lowercase()) {
                    "dark" -> UiModeManager.MODE_NIGHT_YES
                    "light" -> UiModeManager.MODE_NIGHT_NO
                    else -> UiModeManager.MODE_NIGHT_AUTO
                }
                it.setApplicationNightMode(targetMode)
            }
        }

        // 2. Activity 窗口背景全版本保障：显式指定窗口背景，避免首帧渲染前的短暂闪白/闪黑
        val backgroundRes = when (mode.lowercase()) {
            "dark" -> R.drawable.launch_background_dark
            "light" -> R.drawable.launch_background_light
            else -> R.drawable.launch_background
        }
        window.setBackgroundDrawableResource(backgroundRes)
    }
}
