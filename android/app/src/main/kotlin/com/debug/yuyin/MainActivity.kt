package com.debug.yuyin

import android.app.Activity
import android.app.UiModeManager
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.MediaPlayer
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import android.provider.Settings
import android.view.Display
import android.view.WindowManager
import androidx.core.content.FileProvider
import androidx.documentfile.provider.DocumentFile
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import com.debug.yuyin.storage.StorageBridge
import java.io.File
import java.io.FileInputStream
import java.io.IOException

class MainActivity : FlutterActivity() {
    private val themeChannel = "com.debug.yuyin/theme"
    private val audioChannel = "com.debug.yuyin/audio_player"
    private var mediaPlayer: MediaPlayer? = null
    private var currentPlayingUrl: String? = null
    private var audioMethodChannel: MethodChannel? = null
    private val appChannel = "com.debug.yuyin/app"
    private val storageChannel = "com.debug.yuyin/storage"
    private val installerChannel = "com.debug.yuyin/app_installer"
    private val displayModeChannel = "com.debug.yuyin/display_mode"

    private val requestCodeInstallPermission = 2002
    private var pendingApkPathForInstall: String? = null

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
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, installerChannel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCpuAbi" -> {
                        val abis = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            Build.SUPPORTED_ABIS.toList()
                        } else {
                            listOf(Build.CPU_ABI)
                        }
                        result.success(abis)
                    }
                    "checkInstallPermission" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            result.success(packageManager.canRequestPackageInstalls())
                        } else {
                            result.success(true)
                        }
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK path is empty", null)
                            return@setMethodCallHandler
                        }
                        val success = triggerInstallApk(filePath)
                        result.success(success)
                    }
                    else -> result.notImplemented()
                }
            }

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
                                    // 自定义 SAF 目录保存（支持逐级作者/分类子目录）
                                    var targetDir = DocumentFile.fromTreeUri(this, Uri.parse(treeUri))
                                        ?: throw IOException("无法访问目标自定义文件夹")
                                    for (name in subDirNames) {
                                        if (name.isBlank()) continue
                                        val existing = targetDir.findFile(name)
                                        targetDir = if (existing != null && existing.isDirectory) {
                                            existing
                                        } else {
                                            targetDir.createDirectory(name)
                                                ?: throw IOException("无法创建子文件夹: $name")
                                        }
                                    }
                                    val mimeType = getMimeType(fileName, mediaType)
                                    val targetDoc = targetDir.createFile(mimeType, fileName)
                                        ?: throw IOException("无法在目标文件夹创建文件: $fileName")

                                    contentResolver.openOutputStream(targetDoc.uri)?.use { out ->
                                        FileInputStream(srcFile).use { inStream ->
                                            inStream.copyTo(out)
                                        }
                                    } ?: throw IOException("无法写入自定义文件数据")

                                    try {
                                        MediaScannerConnection.scanFile(this, arrayOf(targetDoc.uri.path), arrayOf(mimeType), null)
                                    } catch (_: Exception) {}
                                } else if (collection == "downloads" && !relativePath.isNullOrBlank()) {
                                    // 主页链接：Download/YuYin/<作者>/<Movies|Pictures|Music>/
                                    StorageBridge.saveToDownloads(
                                        this,
                                        srcFile,
                                        fileName,
                                        getMimeType(fileName, mediaType),
                                        relativePath
                                    )
                                } else {
                                    // 默认分类目录保存 (Movies/YuYin/, Pictures/YuYin/, Music/YuYin/)
                                    saveToDefaultDirectory(srcFile, mediaType, fileName)
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

        // 4. 原生音频试听播放器通道
        audioMethodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, audioChannel).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "play" -> {
                        val url = call.argument<String>("url")
                        if (url.isNullOrBlank()) {
                            result.error("INVALID_URL", "Audio URL is empty", null)
                            return@setMethodCallHandler
                        }
                        try {
                            if (currentPlayingUrl == url && mediaPlayer != null) {
                                if (mediaPlayer?.isPlaying == false) {
                                    mediaPlayer?.start()
                                    invokeMethod("onPlayerStateChanged", mapOf("state" to "playing"))
                                }
                                result.success(true)
                                return@setMethodCallHandler
                            }

                            // 停止并清理前一个播放器实例
                            mediaPlayer?.let {
                                try {
                                    if (it.isPlaying) it.stop()
                                    it.release()
                                } catch (_: Exception) {}
                            }
                            mediaPlayer = null
                            currentPlayingUrl = url

                            invokeMethod("onPlayerStateChanged", mapOf("state" to "buffering"))

                            val mp = MediaPlayer().apply {
                                setAudioAttributes(
                                    AudioAttributes.Builder()
                                        .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
                                        .setUsage(AudioAttributes.USAGE_MEDIA)
                                        .build()
                                )
                                val rawHeaders = call.argument<Map<String, String>>("headers")
                                val headers = HashMap<String, String>()
                                headers["User-Agent"] = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36"
                                rawHeaders?.let { headers.putAll(it) }

                                setDataSource(context, Uri.parse(url), headers)
                                setOnPreparedListener { preparedMp ->
                                    preparedMp.start()
                                    invokeMethod(
                                        "onPlayerStateChanged",
                                        mapOf(
                                            "state" to "playing",
                                            "duration" to preparedMp.duration
                                        )
                                    )
                                }
                                setOnCompletionListener {
                                    invokeMethod("onPlayerStateChanged", mapOf("state" to "completed"))
                                }
                                setOnErrorListener { _, what, extra ->
                                    invokeMethod(
                                        "onPlayerStateChanged",
                                        mapOf("state" to "error", "message" to "what=$what, extra=$extra")
                                    )
                                    true
                                }
                                prepareAsync()
                            }
                            mediaPlayer = mp
                            result.success(true)
                        } catch (e: Exception) {
                            invokeMethod("onPlayerStateChanged", mapOf("state" to "error", "message" to e.message))
                            result.error("PLAY_ERROR", e.message, null)
                        }
                    }
                    "pause" -> {
                        try {
                            if (mediaPlayer?.isPlaying == true) {
                                mediaPlayer?.pause()
                                invokeMethod("onPlayerStateChanged", mapOf("state" to "paused"))
                            }
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("PAUSE_ERROR", e.message, null)
                        }
                    }
                    "stop" -> {
                        try {
                            mediaPlayer?.let {
                                if (it.isPlaying) it.stop()
                                it.release()
                            }
                            mediaPlayer = null
                            currentPlayingUrl = null
                            invokeMethod("onPlayerStateChanged", mapOf("state" to "idle"))
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("STOP_ERROR", e.message, null)
                        }
                    }
                    "seek" -> {
                        val pos = call.argument<Int>("position") ?: 0
                        try {
                            mediaPlayer?.seekTo(pos)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("SEEK_ERROR", e.message, null)
                        }
                    }
                    "getPosition" -> {
                        try {
                            val pos = mediaPlayer?.currentPosition ?: 0
                            val dur = mediaPlayer?.duration ?: 0
                            result.success(mapOf("position" to pos, "duration" to dur))
                        } catch (e: Exception) {
                            result.success(mapOf("position" to 0, "duration" to 0))
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        }

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

    override fun onDestroy() {
        try {
            mediaPlayer?.let {
                if (it.isPlaying) it.stop()
                it.release()
            }
            mediaPlayer = null
        } catch (_: Exception) {}
        super.onDestroy()
    }

    override fun onResume() {
        super.onResume()
        // 若从安装未知应用权限设置页返回且已有暂存安装包，自动续装不断流
        val pendingPath = pendingApkPathForInstall
        if (pendingPath != null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            if (packageManager.canRequestPackageInstalls()) {
                pendingApkPathForInstall = null
                triggerInstallApk(pendingPath)
            }
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        if (requestCode == requestCodeInstallPermission) {
            val pendingPath = pendingApkPathForInstall
            if (pendingPath != null) {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O && packageManager.canRequestPackageInstalls()) {
                    pendingApkPathForInstall = null
                    triggerInstallApk(pendingPath)
                }
            }
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

    private fun saveToDefaultDirectory(srcFile: File, mediaType: String, fileName: String) {
        when (mediaType.lowercase()) {
            "video" -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Video.Media.DISPLAY_NAME, fileName)
                        put(MediaStore.Video.Media.MIME_TYPE, "video/mp4")
                        put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/YuYin/")
                        put(MediaStore.Video.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Video.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IOException("无法在系统媒体库创建视频记录")
                    contentResolver.openOutputStream(uri)?.use { out ->
                        FileInputStream(srcFile).use { it.copyTo(out) }
                    } ?: throw IOException("无法写入视频数据")
                    values.clear()
                    values.put(MediaStore.Video.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                } else {
                    val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MOVIES), "YuYin")
                    if (!dir.exists()) dir.mkdirs()
                    val destFile = File(dir, fileName)
                    srcFile.copyTo(destFile, overwrite = true)
                    MediaScannerConnection.scanFile(this, arrayOf(destFile.absolutePath), arrayOf("video/mp4"), null)
                }
            }
            "image" -> {
                val mimeType = when {
                    fileName.endsWith(".png", ignoreCase = true) -> "image/png"
                    fileName.endsWith(".webp", ignoreCase = true) -> "image/webp"
                    else -> "image/jpeg"
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Images.Media.DISPLAY_NAME, fileName)
                        put(MediaStore.Images.Media.MIME_TYPE, mimeType)
                        put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/YuYin/")
                        put(MediaStore.Images.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Images.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IOException("无法在系统媒体库创建图片记录")
                    contentResolver.openOutputStream(uri)?.use { out ->
                        FileInputStream(srcFile).use { it.copyTo(out) }
                    } ?: throw IOException("无法写入图片数据")
                    values.clear()
                    values.put(MediaStore.Images.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                } else {
                    val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_PICTURES), "YuYin")
                    if (!dir.exists()) dir.mkdirs()
                    val destFile = File(dir, fileName)
                    srcFile.copyTo(destFile, overwrite = true)
                    MediaScannerConnection.scanFile(this, arrayOf(destFile.absolutePath), arrayOf(mimeType), null)
                }
            }
            "audio" -> {
                val mimeType = when {
                    fileName.endsWith(".m4a", ignoreCase = true) -> "audio/mp4"
                    fileName.endsWith(".wav", ignoreCase = true) -> "audio/wav"
                    else -> "audio/mpeg"
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    val values = ContentValues().apply {
                        put(MediaStore.Audio.Media.DISPLAY_NAME, fileName)
                        put(MediaStore.Audio.Media.MIME_TYPE, mimeType)
                        put(MediaStore.Audio.Media.RELATIVE_PATH, "Music/YuYin/")
                        put(MediaStore.Audio.Media.IS_PENDING, 1)
                    }
                    val uri = contentResolver.insert(MediaStore.Audio.Media.EXTERNAL_CONTENT_URI, values)
                        ?: throw IOException("无法在系统媒体库创建音频记录")
                    contentResolver.openOutputStream(uri)?.use { out ->
                        FileInputStream(srcFile).use { it.copyTo(out) }
                    } ?: throw IOException("无法写入音频数据")
                    values.clear()
                    values.put(MediaStore.Audio.Media.IS_PENDING, 0)
                    contentResolver.update(uri, values, null, null)
                } else {
                    val dir = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_MUSIC), "YuYin")
                    if (!dir.exists()) dir.mkdirs()
                    val destFile = File(dir, fileName)
                    srcFile.copyTo(destFile, overwrite = true)
                    MediaScannerConnection.scanFile(this, arrayOf(destFile.absolutePath), arrayOf(mimeType), null)
                }
            }
            else -> throw IllegalArgumentException("不支持的媒体类型: $mediaType")
        }
    }

    private fun getMimeType(fileName: String, mediaType: String): String {
        return when (mediaType.lowercase()) {
            "video" -> "video/mp4"
            "audio" -> {
                when {
                    fileName.endsWith(".m4a", ignoreCase = true) -> "audio/mp4"
                    fileName.endsWith(".wav", ignoreCase = true) -> "audio/wav"
                    else -> "audio/mpeg"
                }
            }
            else -> {
                when {
                    fileName.endsWith(".png", ignoreCase = true) -> "image/png"
                    fileName.endsWith(".webp", ignoreCase = true) -> "image/webp"
                    else -> "image/jpeg"
                }
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

    private fun triggerInstallApk(filePath: String): Boolean {
        try {
            val apkFile = File(filePath)
            if (!apkFile.exists()) return false

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                if (!packageManager.canRequestPackageInstalls()) {
                    pendingApkPathForInstall = filePath
                    val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                        data = Uri.parse("package:$packageName")
                        addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                    }
                    startActivityForResult(intent, requestCodeInstallPermission)
                    return false
                }
            }

            pendingApkPathForInstall = null
            val apkUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(this, "$packageName.fileprovider", apkFile)
            } else {
                Uri.fromFile(apkFile)
            }

            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            startActivity(installIntent)
            return true
        } catch (e: Exception) {
            e.printStackTrace()
            return false
        }
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
