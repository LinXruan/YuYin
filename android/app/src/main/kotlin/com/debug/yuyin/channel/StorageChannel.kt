package com.debug.yuyin.channel

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.provider.DocumentsContract
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import com.debug.yuyin.storage.MediaSaver
import com.debug.yuyin.storage.StorageBridge
import java.io.File
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/// 存储通道：SAF 目录选择、媒体落盘、保存结果查询与旧版权限申请。
class StorageChannel(private val activity: Activity) {
    private var pendingPickResult: MethodChannel.Result? = null
    private var pendingPermissionResult: MethodChannel.Result? = null
    private val io: ExecutorService = Executors.newSingleThreadExecutor()

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "pickDirectory" -> pickDirectory(result)
                    "saveMedia" -> saveMedia(call, result)
                    "querySavedMedia" -> querySavedMedia(call, result)
                    "openMediaLocation" -> openMediaLocation(call, result)
                    "hasStorageAccess" -> result.success(hasStorageAccess())
                    "requestStorageAccess" -> requestStorageAccess(result)
                    else -> result.notImplemented()
                }
            }
    }

    private fun pickDirectory(result: MethodChannel.Result) {
        if (pendingPickResult != null) {
            result.error("BUSY", "Another directory picker is active", null)
            return
        }
        pendingPickResult = result
        try {
            val intent = Intent(Intent.ACTION_OPEN_DOCUMENT_TREE).apply {
                addFlags(
                    Intent.FLAG_GRANT_READ_URI_PERMISSION or
                        Intent.FLAG_GRANT_WRITE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PERSISTABLE_URI_PERMISSION or
                        Intent.FLAG_GRANT_PREFIX_URI_PERMISSION
                )
            }
            activity.startActivityForResult(intent, REQUEST_CODE_PICK_DIRECTORY)
        } catch (e: Exception) {
            pendingPickResult = null
            result.error("PICK_FAILED", e.message, null)
        }
    }

    private fun saveMedia(call: MethodCall, result: MethodChannel.Result) {
        val filePath = call.argument<String>("filePath")
        val mediaType = call.argument<String>("mediaType") ?: "video"
        val treeUri = call.argument<String>("treeUri")
        val relativePath = call.argument<String>("relativePath")
        val subDirNames = call.argument<List<String>>("subDirNames") ?: emptyList()
        val collection = call.argument<String>("collection") ?: "auto"
        val fileName = call.argument<String>("fileName")
            ?: "file_${System.currentTimeMillis()}"

        if (filePath.isNullOrBlank()) {
            result.error("INVALID_ARGS", "filePath is required", null)
            return
        }

        io.execute {
            try {
                val srcFile = File(filePath)
                if (!srcFile.exists()) {
                    replyError(result, "FILE_NOT_FOUND", "Source file does not exist")
                    return@execute
                }
                when {
                    !treeUri.isNullOrBlank() -> MediaSaver.saveToTree(
                        activity, treeUri, subDirNames, srcFile, fileName, mediaType
                    )
                    collection == "downloads" && !relativePath.isNullOrBlank() ->
                        MediaSaver.saveToDownloads(
                            activity,
                            srcFile,
                            fileName,
                            MediaSaver.mimeTypeFor(fileName, mediaType),
                            relativePath
                        )
                    else -> MediaSaver.saveToDefaultDirectory(
                        activity, srcFile, mediaType, fileName
                    )
                }
                replySuccess(result, true)
            } catch (e: Exception) {
                replyError(result, "SAVE_FAILED", e.message)
            }
        }
    }

    private fun querySavedMedia(call: MethodCall, result: MethodChannel.Result) {
        val rawQueries = (call.arguments as? Map<*, *>)?.get("queries") as? List<*>
            ?: emptyList<Any>()
        val queries = rawQueries.mapNotNull { it as? Map<*, *> }.map { raw ->
            raw.entries.associate { it.key.toString() to it.value }
        }
        io.execute {
            try {
                replySuccess(result, StorageBridge.querySavedMedia(activity, queries))
            } catch (e: Exception) {
                replyError(result, "QUERY_FAILED", e.message)
            }
        }
    }

    private fun openMediaLocation(call: MethodCall, result: MethodChannel.Result) {
        val contentUri = call.argument<String>("contentUri")
        val folderUri = call.argument<String>("folderUri")
        val mimeType = call.argument<String>("mimeType") ?: "*/*"
        try {
            replySuccess(
                result,
                StorageBridge.openMediaLocation(activity, contentUri, folderUri, mimeType)
            )
        } catch (e: Exception) {
            replyError(result, "OPEN_FAILED", e.message)
        }
    }

    /// 处理 SAF 目录选择结果；返回 true 表示已消费该 requestCode
    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != REQUEST_CODE_PICK_DIRECTORY) return false
        val callback = pendingPickResult
        pendingPickResult = null
        if (resultCode == Activity.RESULT_OK && data?.data != null) {
            val uri = data.data!!
            try {
                val flags = Intent.FLAG_GRANT_READ_URI_PERMISSION or
                    Intent.FLAG_GRANT_WRITE_URI_PERMISSION
                activity.contentResolver.takePersistableUriPermission(uri, flags)
            } catch (_: Exception) {
            }
            callback?.success(
                mapOf("uri" to uri.toString(), "displayPath" to displayPathOf(uri))
            )
        } else {
            callback?.success(null)
        }
        return true
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != REQUEST_CODE_STORAGE_PERMISSION) return false
        val callback = pendingPermissionResult
        pendingPermissionResult = null
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        callback?.success(granted)
        return true
    }

    fun release() {
        io.shutdown()
        pendingPickResult = null
        pendingPermissionResult = null
    }

    private fun hasStorageAccess(): Boolean {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) return true
        return activity.checkSelfPermission(Manifest.permission.WRITE_EXTERNAL_STORAGE) ==
            PackageManager.PERMISSION_GRANTED
    }

    private fun requestStorageAccess(result: MethodChannel.Result) {
        if (hasStorageAccess()) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("BUSY", "Another permission request is active", null)
            return
        }
        pendingPermissionResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.WRITE_EXTERNAL_STORAGE),
            REQUEST_CODE_STORAGE_PERMISSION
        )
    }

    private fun replySuccess(result: MethodChannel.Result, value: Any?) {
        activity.runOnUiThread { result.success(value) }
    }

    private fun replyError(result: MethodChannel.Result, code: String, message: String?) {
        activity.runOnUiThread { result.error(code, message, null) }
    }

    private fun displayPathOf(uri: Uri): String {
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
        } catch (_: Exception) {
        }
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

    private companion object {
        const val CHANNEL = "com.debug.yuyin/storage"
        const val REQUEST_CODE_PICK_DIRECTORY = 2001
        const val REQUEST_CODE_STORAGE_PERMISSION = 2003
    }
}
