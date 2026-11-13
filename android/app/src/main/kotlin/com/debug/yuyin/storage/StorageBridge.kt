package com.debug.yuyin.storage

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.io.FileInputStream
import java.io.IOException

/// 原生存储辅助：主页 Download 目录保存、保存结果查询、文件夹/文件打开
object StorageBridge {

    private data class QuerySpec(
        val type: String,
        val treeUri: String?,
        val relativePath: String?,
        val subDirNames: List<String>,
        val namePrefix: String?,
        val collection: String,
        val displayPath: String
    ) {
        companion object {
            fun fromMap(map: Map<String, Any?>): QuerySpec {
                val subDirs = (map["subDirNames"] as? List<*>)
                    ?.mapNotNull { it?.toString() }
                    ?: emptyList()
                return QuerySpec(
                    type = map["type"]?.toString() ?: "video",
                    treeUri = map["treeUri"]?.toString(),
                    relativePath = map["relativePath"]?.toString(),
                    subDirNames = subDirs,
                    namePrefix = map["namePrefix"]?.toString(),
                    collection = map["collection"]?.toString() ?: "auto",
                    displayPath = map["displayPath"]?.toString() ?: ""
                )
            }
        }
    }

    /// 保存到 MediaStore.Downloads（Android 10+）或传统 Download 目录（Android 9-）
    @Throws(IOException::class)
    fun saveToDownloads(
        context: Context,
        srcFile: File,
        fileName: String,
        mimeType: String,
        relativePath: String
    ) {
        val cleanRelative = relativePath.trim().trimStart('/')
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, fileName)
                put(MediaStore.Downloads.MIME_TYPE, mimeType)
                put(MediaStore.Downloads.RELATIVE_PATH, cleanRelative)
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
            val uri = context.contentResolver.insert(
                MediaStore.Downloads.EXTERNAL_CONTENT_URI,
                values
            ) ?: throw IOException("无法在 Download 目录创建文件记录")

            context.contentResolver.openOutputStream(uri)?.use { out ->
                FileInputStream(srcFile).use { input ->
                    input.copyTo(out)
                }
            } ?: throw IOException("无法写入 Download 文件数据")

            values.clear()
            values.put(MediaStore.Downloads.IS_PENDING, 0)
            context.contentResolver.update(uri, values, null, null)
            return
        }

        // Android 9 及以下：直接写入公共 Download 目录
        val legacyRelative = cleanRelative.removePrefix("Download/")
        val root = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOWNLOADS
        )
        val targetDir = File(root, legacyRelative.trimEnd('/'))
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IOException("无法创建 Download 子目录")
        }
        val destFile = File(targetDir, fileName)
        srcFile.copyTo(destFile, overwrite = true)
        try {
            MediaScannerConnection.scanFile(
                context,
                arrayOf(destFile.absolutePath),
                arrayOf(mimeType),
                null
            )
        } catch (_: Exception) {
        }
    }

    /// 批量查询保存位置中是否存在对应资源
    fun querySavedMedia(
        context: Context,
        queries: List<Map<String, Any?>>
    ): List<Map<String, Any?>> {
        return queries.map { raw ->
            val spec = QuerySpec.fromMap(raw)
            try {
                when {
                    !spec.treeUri.isNullOrBlank() -> querySaf(context, spec)
                    spec.collection == "downloads" -> queryDefault(context, spec)
                    else -> queryDefault(context, spec)
                }
            } catch (e: Exception) {
                notFound(spec)
            }
        }
    }

    /// 优先跳转文件管理器文件夹，失败时打开文件
    fun openMediaLocation(
        context: Context,
        contentUri: String?,
        folderUri: String?,
        mimeType: String
    ): Boolean {
        if (!folderUri.isNullOrBlank()) {
            val folderTypes = listOf(
                DocumentsContract.Document.MIME_TYPE_DIR,
                "resource/folder"
            )
            for (type in folderTypes) {
                if (tryOpen(context, Uri.parse(folderUri), type)) return true
            }
        }

        if (!contentUri.isNullOrBlank()) {
            val type = if (mimeType.isBlank()) "*/*" else mimeType
            if (tryOpen(context, Uri.parse(contentUri), type)) return true
        }
        return false
    }

    private fun tryOpen(context: Context, uri: Uri, mimeType: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, mimeType)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            // Android 11+ 包可见性会限制 resolveActivity，直接启动并捕获异常更可靠
            context.startActivity(intent)
            true
        } catch (_: Exception) {
            false
        }
    }

    private fun querySaf(context: Context, spec: QuerySpec): Map<String, Any?> {
        var dir = DocumentFile.fromTreeUri(context, Uri.parse(spec.treeUri))
            ?: return notFound(spec)
        for (name in spec.subDirNames) {
            if (name.isBlank()) continue
            dir = dir.findFile(name) ?: return notFound(spec)
            if (!dir.isDirectory) return notFound(spec)
        }

        val prefix = spec.namePrefix
        val files = dir.listFiles().filter { file ->
            file.isFile &&
                matchesType(context, file, spec.type) &&
                (prefix.isNullOrBlank() || (file.name?.startsWith(prefix) == true))
        }
        val latest = files.maxByOrNull { it.lastModified() }
        return mapOf(
            "type" to spec.type,
            "found" to files.isNotEmpty(),
            "count" to files.size,
            "uri" to latest?.uri?.toString(),
            "folderUri" to dir.uri.toString(),
            "displayPath" to spec.displayPath
        )
    }

    private fun queryDefault(context: Context, spec: QuerySpec): Map<String, Any?> {
        val collectionUri = collectionUriFor(spec.type, spec.collection)
        val selectionParts = mutableListOf<String>()
        val selectionArgs = mutableListOf<String>()

        if (!spec.relativePath.isNullOrBlank()) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                selectionParts.add(MediaStore.MediaColumns.RELATIVE_PATH + " = ?")
                selectionArgs.add(spec.relativePath.trimStart('/'))
            } else {
                val basePath = Environment.getExternalStorageDirectory().absolutePath +
                    "/" + spec.relativePath.trimStart('/')
                selectionParts.add(MediaStore.MediaColumns.DATA + " LIKE ?")
                selectionArgs.add(basePath + "%")
            }
        }

        selectionParts.add(MediaStore.MediaColumns.MIME_TYPE + " LIKE ?")
        selectionArgs.add(mimePrefix(spec.type) + "%")

        if (!spec.namePrefix.isNullOrBlank()) {
            selectionParts.add(MediaStore.MediaColumns.DISPLAY_NAME + " LIKE ? ESCAPE '!'")
            selectionArgs.add(escapeLike(spec.namePrefix) + "%")
        }

        val projection = arrayOf(
            MediaStore.MediaColumns._ID,
            MediaStore.MediaColumns.DISPLAY_NAME
        )
        val cursor = context.contentResolver.query(
            collectionUri,
            projection,
            selectionParts.joinToString(" AND "),
            selectionArgs.toTypedArray(),
            MediaStore.MediaColumns.DATE_MODIFIED + " DESC"
        )

        cursor?.use {
            val count = it.count
            if (count > 0 && it.moveToFirst()) {
                val id = it.getLong(
                    it.getColumnIndexOrThrow(MediaStore.MediaColumns._ID)
                )
                val fileUri = ContentUris.withAppendedId(collectionUri, id).toString()
                return mapOf(
                    "type" to spec.type,
                    "found" to true,
                    "count" to count,
                    "uri" to fileUri,
                    "folderUri" to buildExternalFolderUri(spec.relativePath),
                    "displayPath" to spec.displayPath
                )
            }
        }
        return notFound(spec)
    }

    private fun collectionUriFor(type: String, collection: String): Uri {
        if (collection == "downloads") {
            return MediaStore.Files.getContentUri("external")
        }
        return when (type) {
            "image" -> MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            "audio" -> MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
            else -> MediaStore.Video.Media.EXTERNAL_CONTENT_URI
        }
    }

    private fun matchesType(context: Context, file: DocumentFile, type: String): Boolean {
        val mime = context.contentResolver.getType(file.uri) ?: ""
        if (mime.startsWith(mimePrefix(type))) return true
        val extension = file.name
            ?.substringAfterLast('.', "")
            ?.lowercase()
            ?: ""
        return when (type) {
            "image" -> extension in listOf("jpg", "jpeg", "png", "webp", "gif", "heic")
            "audio" -> extension in listOf("mp3", "m4a", "wav", "aac", "ogg", "flac")
            else -> extension in listOf("mp4", "mov", "m4v", "flv", "mkv")
        }
    }

    private fun mimePrefix(type: String): String {
        return when (type) {
            "image" -> "image/"
            "audio" -> "audio/"
            else -> "video/"
        }
    }

    private fun escapeLike(value: String): String {
        return value
            .replace("!", "!!")
            .replace("%", "!%")
            .replace("_", "!_")
    }

    private fun buildExternalFolderUri(relativePath: String?): String? {
        if (relativePath.isNullOrBlank()) return null
        return try {
            DocumentsContract.buildDocumentUri(
                "com.android.externalstorage.documents",
                "primary:" + relativePath.trim('/')
            ).toString()
        } catch (_: Exception) {
            null
        }
    }

    private fun notFound(spec: QuerySpec): Map<String, Any?> {
        return mapOf(
            "type" to spec.type,
            "found" to false,
            "count" to 0,
            "uri" to null,
            "folderUri" to buildExternalFolderUri(spec.relativePath),
            "displayPath" to spec.displayPath
        )
    }
}
