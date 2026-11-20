package com.debug.yuyin

import android.app.Activity
import android.app.UiModeManager
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.DocumentsContract
import android.view.Display
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.debug.yuyin.audio.AudioPreviewPlayer
import com.debug.yuyin.install.InstallerChannel
import com.debug.yuyin.storage.MediaSaver
import com.debug.yuyin.storage.StorageBridge
import java.io.File
import java.io.IOException

class MainActivity : FlutterActivity() {
    private val themeChannel = "com.debug.yuyin/theme"
    private val audioChannel = "com.debug.yuyin/audio_player"
    private var audioPreviewPlayer: AudioPreviewPlayer? = null
    private val appChannel = "com.debug.yuyin/app"
    private val storageChannel = "com.debug.yuyin/storage"
    private val displayModeChannel = "com.debug.yuyin/display_mode"

    private var installerChannel: InstallerChannel? = null

    private val requestCodePickDirectory = 2001
    private var pendingDirPickerResult: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // 在最早期读取并设置启动背景与自适应高刷新率，确保 cold start 无缝匹配最高硬件刷新率
        applySavedThemeMode()
        enableAdaptiveHighRefreshRate()
        super.onCreate(savedInstanceState)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (hasFocus) {
            enableAdaptiveHighRefreshRate()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // 1. 主题切换通道
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

        // 2. 应用通用能力通道（外部跳转等）
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

        // 2.5 应用更新与安装通道
        installerChannel = InstallerChannel(this).also { it.attach(flutterEngine) }

        // 3. 存储与 SAF 目录选择器通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, storageChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectory" -> {
                        if (pendingDirPickerResult != null) {
                            result.error("BUSY", "Another directory picker is active", null)
                            return@setMethodCallHandler
                        }
                        pendingDirPickerResult = result
                        try {
                            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                                addFlags(
                                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                                    Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                                )
                            }
                            startActivityForResult(intent, requestCodePickDirectory)
                        } catch (e: Exception) {
                            pendingDirPickerResult = null
                            result.error("PICK_FAILED", e.message, null)
                        }
                    }
                    "saveMedia" -> {
                        val filePath = call.argument<String>("filePath")
                        val mediaType = call.argument<String>("mediaType") ?: "video"
                        val treeUri = call.argument<String>("treeUri")
                        val relativePath = call.argument<String>("relativePath")
                        val subDirNames = call.argument<List<String>>("subDirNames") ?: emptyList()
                        val collection = call.argument<String>("collection") ?: "auto"
                        val fileName = call.argument<String>("fileName") ?: "file_${System.currentTimeMillis()}"

                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_ARGS", "filePath is required", null)
                            return@setMethodCallHandler
                        }

                        Thread {
                            try {
                                val srcFile = File(filePath)
                                if (!srcFile.exists()) {
                                    runOnUiThread { result.error("FILE_NOT_FOUND", "Source file does not exist", null) }
                                    return@Thread
                                }

                                if (!treeUri.isNullOrBlank()) {
                                    // 自定义 SAF 目录保存（逐级作者/分类子目录，失败自动删除空壳文件）
                                    MediaSaver.saveToTree(
                                        this,
                                        treeUri,
                                        subDirNames,
                                        srcFile,
                                        fileName,
                                        mediaType
                                    )
                                } else if (collection == "downloads" && !relativePath.isNullOrBlank()) {
                                    // 主页链接：Download/YuYin/<作者>/<Movies|Pictures|Music>/
                                    MediaSaver.saveToDownloads(
                                        this,
                                        srcFile,
                                        fileName,
                                        MediaSaver.mimeTypeFor(fileName, mediaType),
                                        relativePath
                                    )
                                } else {
                                    // 默认分类目录保存 (Movies/YuYin/, Pictures/YuYin/, Music/YuYin/)
                                    MediaSaver.saveToDefaultDirectory(
                                        this,
                                        srcFile,
                                        mediaType,
                                        fileName
                                    )
                                }
                                runOnUiThread { result.success(true) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("SAVE_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                    "querySavedMedia" -> {
                        val rawQueries = (call.arguments as? Map<*, *>)?.get("queries") as? List<*>
                            ?: emptyList<Any>()
                        val queries = rawQueries.mapNotNull { it as? Map<*, *> }.map { raw ->
                            raw.entries.associate { it.key.toString() to it.value }
                        }
                        Thread {
                            try {
                                val results = StorageBridge.querySavedMedia(this, queries)
                                runOnUiThread { result.success(results) }
                            } catch (e: Exception) {
                                runOnUiThread { result.error("QUERY_FAILED", e.message, null) }
                            }
                        }.start()
                    }
                    "openMediaLocation" -> {
                        val contentUri = call.argument<String>("contentUri")
                        val folderUri = call.argument<String>("folderUri")
                        val mimeType = call.argument<String>("mimeType") ?: "*/*"
                        try {
                            val opened = StorageBridge.openMediaLocation(
                                this,
                                contentUri,
                                folderUri,
                                mimeType
                            )
                            result.success(opened)
                        } catch (e: Exception) {
                            result.error("OPEN_FAILED", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }

        // 4. 原生音频试听播放器通道（状态机见 AudioPreviewPlayer）
        audioPreviewPlayer = AudioPreviewPlayer(
            this,
            MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannel)
        )

        // 5. 屏幕刷新率通道
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, displayModeChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getDisplayInfo" -> {
                        result.success(getDisplayInfo())
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStop() {
        // 退到后台时暂停试听，避免无交互继续播放
        audioPreviewPlayer?.pauseForBackground()
        super.onStop()
    }

    override fun onDestroy() {
        audioPreviewPlayer?.release()
        audioPreviewPlayer = null
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        // 若从安装未知应用权限设置页返回且已有暂存安装包，自动续装不断流
        installerChannel?.resumePendingInstall()
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (installerChannel?.onActivityResult(requestCode) == true) {
            // 已消费未知来源权限页返回
        }
        if (requestCode == requestCodePickDirectory) {
            val cb = pendingDirPickerResult
            pendingDirPickerResult = null
            if (resultCode == Activity.RESULT_OK && data?.data != null) {
                val uri = data.data!!
                try {
                    val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                    contentResolver.takePersistableUriPermission(uri, flags)
                } catch (_: Exception) {}
                val displayPath = getDisplayPathFromTreeUri(uri)
                cb?.success(
                    mapOf(
                        "uri" to uri.toString(),
                        "displayPath" to displayPath
                    )
                )
            } else {
                cb?.success(null)
            }
        }
    }

    private fun getDisplayPathFromTreeUri(uri: Uri): String {
        try {
            val docId = DocumentsContract.getTreeDocumentId(uri)
            if (docId != null) {
                if (docId.startsWith("primary:")) {
                    val sub = docId.substringAfter("primary:").trim('/')
                    return if (sub.isEmpty()) "/" else "/$sub/"
                }
                val parts = docId.split(":", limit = 2)
                if (parts.size == 2) {
                    val sub = parts[1].trim('/')
                    return if (sub.isEmpty()) "/${parts[0]}/" else "/${parts[0]}/$sub/"
                }
                return "/${docId.trim('/')}/"
            }
        } catch (_: Exception) {}

        val path = uri.path ?: ""
        val treeIndex = path.indexOf("/tree/")
        if (treeIndex != -1) {
            val rawDocId = Uri.decode(path.substring(treeIndex + 6))
            if (rawDocId.startsWith("primary:")) {
                val sub = rawDocId.substringAfter("primary:").trim('/')
                return if (sub.isEmpty()) "/" else "/$sub/"
            }
        }
        return "/自定义目录/"
    }

    private fun applySavedThemeMode() {
        try {
            val file = File(filesDir, "theme_mode.flag")
            if (file.exists()) {
                val mode = file.readText().trim()
                applyThemeMode(mode)
            }
        } catch (_: Exception) {}
    }

    private fun applyThemeMode(mode: String) {
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

        val backgroundRes = when (mode.lowercase()) {
            "dark" -> R.drawable.launch_background_dark
            "light" -> R.drawable.launch_background_light
            else -> R.drawable.launch_background
        }
        window.setBackgroundDrawableResource(backgroundRes)
    }

    private fun getTargetDisplay(): Display? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            display
        } else {
            @Suppress("DEPRECATION")
            windowManager.defaultDisplay
        }
    }

    private fun enableAdaptiveHighRefreshRate() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
            return
        }
        try {
            val disp = getTargetDisplay() ?: return
            val currentMode = disp.mode
            val matchingModes = disp.supportedModes.filter {
                it.physicalWidth == currentMode.physicalWidth && it.physicalHeight == currentMode.physicalHeight
            }
            val candidates = if (matchingModes.isNotEmpty()) matchingModes else disp.supportedModes.toList()
            val bestMode = candidates.maxByOrNull { it.refreshRate } ?: return

            val layoutParams = window.attributes
            layoutParams.preferredDisplayModeId = bestMode.modeId
            window.attributes = layoutParams
        } catch (_: Exception) {}
    }

    private fun getDisplayInfo(): Map<String, Any> {
        val map = mutableMapOf<String, Any>()
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            try {
                val disp = getTargetDisplay()
                if (disp != null) {
                    val currentMode = disp.mode
                    map["activeRefreshRate"] = currentMode.refreshRate.toDouble()
                    map["width"] = currentMode.physicalWidth
                    map["height"] = currentMode.physicalHeight

                    val maxHz = disp.supportedModes.maxOfOrNull { it.refreshRate } ?: currentMode.refreshRate
                    map["maxRefreshRate"] = maxHz.toDouble()
                    map["supportedModesCount"] = disp.supportedModes.size
                    return map
                }
            } catch (_: Exception) {}
        }
        map["activeRefreshRate"] = 60.0
        map["maxRefreshRate"] = 60.0
        map["width"] = 0
        map["height"] = 0
        map["supportedModesCount"] = 1
        return map
    }
}