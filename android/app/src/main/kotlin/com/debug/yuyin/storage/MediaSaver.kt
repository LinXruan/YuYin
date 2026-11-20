package com.debug.yuyin.storage

import android.content.ContentValues
import android.content.Context
import android.media.MediaScannerConnection
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import androidx.documentfile.provider.DocumentFile
import java.io.File
import java.io.FileInputStream
import java.io.IOException

/// 媒体落盘：MediaStore、SAF 目录与 Android 9- 公共目录三条通道统一在此维护。
object MediaSaver {

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

            try {
                context.contentResolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(srcFile).use { input ->
                        input.copyTo(out)
                    }
                } ?: throw IOException("无法写入 Download 文件数据")

                values.clear()
                values.put(MediaStore.Downloads.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                // 失败必须删除半成品记录，否则会在媒体库留下 IS_PENDING=1 的僵尸条目
                try {
                    context.contentResolver.delete(uri, null, null)
                } catch (_: Exception) {
                }
                throw e
            }
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
        val destFile = uniqueFile(targetDir, fileName)
        srcFile.copyTo(destFile, overwrite = false)
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

    /// 保存到用户选择的 SAF 目录（逐级创建作者/分类子目录），失败时删除空壳文件
    @Throws(IOException::class)
    fun saveToTree(
        context: Context,
        treeUri: String,
        subDirNames: List<String>,
        srcFile: File,
        fileName: String,
        mediaType: String
    ) {
        val mimeType = mimeTypeFor(fileName, mediaType)
        var targetDir = DocumentFile.fromTreeUri(context, Uri.parse(treeUri))
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
        val targetDoc = targetDir.createFile(mimeType, fileName)
            ?: throw IOException("无法在目标文件夹创建文件: $fileName")
        try {
            context.contentResolver.openOutputStream(targetDoc.uri)?.use { out ->
                FileInputStream(srcFile).use { input -> input.copyTo(out) }
            } ?: throw IOException("无法写入自定义文件数据")
        } catch (e: Exception) {
            // content:// 不是文件路径，MediaScanner 无法修复，直接删除半成品文档
            try {
                targetDoc.delete()
            } catch (_: Exception) {
            }
            throw e
        }
    }

    /// 保存到默认分类目录（Movies/Pictures/Music 下的 YuYin 子目录）
    @Throws(IOException::class)
    fun saveToDefaultDirectory(
        context: Context,
        srcFile: File,
        mediaType: String,
        fileName: String
    ) {
        val relativePath: String
        val collectionUri: Uri
        val mimeType: String
        val legacyDir: String
        when (mediaType.lowercase()) {
            "video" -> {
                relativePath = "Movies/YuYin/"
                collectionUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
                mimeType = "video/mp4"
                legacyDir = Environment.DIRECTORY_MOVIES
            }
            "image" -> {
                relativePath = "Pictures/YuYin/"
                collectionUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
                mimeType = imageMimeType(fileName)
                legacyDir = Environment.DIRECTORY_PICTURES
            }
            "audio" -> {
                relativePath = "Music/YuYin/"
                collectionUri = MediaStore.Audio.Media.EXTERNAL_CONTENT_URI
                mimeType = audioMimeType(fileName)
                legacyDir = Environment.DIRECTORY_MUSIC
            }
            else -> throw IllegalArgumentException("不支持的媒体类型: $mediaType")
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
            val uri = context.contentResolver.insert(collectionUri, values)
                ?: throw IOException("无法在系统媒体库创建记录: $fileName")
            try {
                context.contentResolver.openOutputStream(uri)?.use { out ->
                    FileInputStream(srcFile).use { input -> input.copyTo(out) }
                } ?: throw IOException("无法写入媒体数据: $fileName")
                values.clear()
                values.put(MediaStore.MediaColumns.IS_PENDING, 0)
                context.contentResolver.update(uri, values, null, null)
            } catch (e: Exception) {
                try {
                    context.contentResolver.delete(uri, null, null)
                } catch (_: Exception) {
                }
                throw e
            }
            return
        }

        val root = Environment.getExternalStoragePublicDirectory(legacyDir)
        val targetDir = File(root, "YuYin")
        if (!targetDir.exists() && !targetDir.mkdirs()) {
            throw IOException("无法创建目标目录: $targetDir")
        }
        val destFile = uniqueFile(targetDir, fileName)
        srcFile.copyTo(destFile, overwrite = false)
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

    /// Android 9- 重名时生成 `name (1).ext`，不再静默覆盖已有文件
    private fun uniqueFile(dir: File, fileName: String): File {
        val first = File(dir, fileName)
        if (!first.exists()) return first
        val dot = fileName.lastIndexOf('.')
        val base = if (dot > 0) fileName.substring(0, dot) else fileName
        val extension = if (dot > 0) fileName.substring(dot) else ""
        var index = 1
        while (index < 1000) {
            val candidate = File(dir, "$base ($index)$extension")
            if (!candidate.exists()) return candidate
            index++
        }
        return File(dir, "$base-${System.currentTimeMillis()}$extension")
    }

    /// 统一媒体类型 -> MIME 推导
    fun mimeTypeFor(fileName: String, mediaType: String): String = when (mediaType.lowercase()) {
        "video" -> "video/mp4"
        "audio" -> audioMimeType(fileName)
        else -> imageMimeType(fileName)
    }

    private fun imageMimeType(fileName: String): String = when {
        fileName.endsWith(".png", ignoreCase = true) -> "image/png"
        fileName.endsWith(".webp", ignoreCase = true) -> "image/webp"
        else -> "image/jpeg"
    }

    private fun audioMimeType(fileName: String): String = when {
        fileName.endsWith(".m4a", ignoreCase = true) -> "audio/mp4"
        fileName.endsWith(".wav", ignoreCase = true) -> "audio/wav"
        else -> "audio/mpeg"
    }
}
