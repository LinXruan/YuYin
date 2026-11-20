package com.debug.yuyin.storage

import android.content.ContentUris
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.DocumentsContract
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile

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

    /// 音频优先文件夹；视频/图片优先具体媒体 URI，系统图库会打开该资源
    fun openMediaLocation(
        context: Context,
        contentUri: String?,
        folderUri: String?,
        mimeType: String
    ): Boolean {
        val openFile = {
            if (!contentUri.isNullOrBlank()) {
                val type = if (mimeType.isBlank()) "*/*" else mimeType
                tryOpen(context, Uri.parse(contentUri), type)
            } else false
        }
        val openFolder = {
            var ok = false
            if (!folderUri.isNullOrBlank()) {
                val folderTypes = listOf(
                    DocumentsContract.Document.MIME_TYPE_DIR,
                    "resource/folder"
                )
                for (type in folderTypes) {
                    if (tryOpen(context, Uri.parse(folderUri), type)) {
                        ok = true
                        break
                    }
                }
            }
            ok
        }
        return if (mimeType.startsWith("audio/")) {
            // 音频只定位到所在文件夹，不直接播放
            openFolder()
        } else {
            openFile() || openFolder()
        }
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
        // 单次 Cursor 查询子项：避免 DocumentFile.listFiles() 逐文件 Binder IPC
        val matched = queryChildren(context, dir, spec, prefix)
        val first = matched.minByOrNull { it.first }
        return mapOf(
            "type" to spec.type,
            "found" to matched.isNotEmpty(),
            "count" to matched.size,
            "uri" to first?.second?.toString(),
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

        // 只统计已完成写入的记录，过滤写入中断留下的 IS_PENDING=1 僵尸条目
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            selectionParts.add(MediaStore.MediaColumns.IS_PENDING + " = 0")
        }

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
            MediaStore.MediaColumns.DISPLAY_NAME + " ASC"
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

    /// 用一次 Cursor 查询目录子项；失败时回退 DocumentFile 逐项列举
    private fun queryChildren(
        context: Context,
        dir: DocumentFile,
        spec: QuerySpec,
        prefix: String?
    ): List<Pair<String, Uri>> {
        try {
            val childrenUri = DocumentsContract.buildChildDocumentsUriUsingTree(
                dir.uri,
                DocumentsContract.getDocumentId(dir.uri)
            )
            val projection = arrayOf(
                DocumentsContract.Document.COLUMN_DOCUMENT_ID,
                DocumentsContract.Document.COLUMN_DISPLAY_NAME,
                DocumentsContract.Document.COLUMN_MIME_TYPE
            )
            val result = mutableListOf<Pair<String, Uri>>()
            context.contentResolver.query(childrenUri, projection, null, null, null)?.use { cursor ->
                while (cursor.moveToNext()) {
                    val docId = cursor.getString(0) ?: continue
                    val name = cursor.getString(1) ?: continue
                    val mime = cursor.getString(2) ?: ""
                    if (mime == DocumentsContract.Document.MIME_TYPE_DIR) continue
                    if (!matchesTypeName(mime, name, spec.type)) continue
                    if (!prefix.isNullOrBlank() && !name.startsWith(prefix)) continue
                    result.add(
                        name to DocumentsContract.buildDocumentUriUsingTree(dir.uri, docId)
                    )
                }
            }
            if (result.isNotEmpty()) return result
            // 空结果可能是目录 URI 解析差异，回退一次逐项列举，避免误报未保存
        } catch (_: Exception) {
            // 回退 DocumentFile 列举
        }
        return try {
            dir.listFiles()
                .filter { file ->
                    file.isFile &&
                        matchesType(context, file, spec.type) &&
                        (prefix.isNullOrBlank() ||
                            (file.name?.startsWith(prefix) == true))
                }
                .mapNotNull { file -> file.name?.let { it to file.uri } }
        } catch (_: Exception) {
            emptyList()
        }
    }

    private fun matchesTypeName(mime: String, name: String, type: String): Boolean {
        if (mime.startsWith(mimePrefix(type))) return true
        val extension = name.substringAfterLast('.', "").lowercase()
        return when (type) {
            "image" -> extension in listOf("jpg", "jpeg", "png", "webp", "gif", "heic")
            "audio" -> extension in listOf("mp3", "m4a", "wav", "aac", "ogg", "flac")
            else -> extension in listOf("mp4", "mov", "m4v", "flv", "mkv")
        }
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