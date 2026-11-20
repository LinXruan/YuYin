package com.debug.yuyin.install

import android.app.Activity
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// 应用安装通道：APK 安装、未知来源权限申请与从设置页返回后的自动续装。
class InstallerChannel(private val activity: Activity) {
    private var pendingApkPath: String? = null

    fun attach(engine: FlutterEngine) {
        MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCpuAbi" -> {
                        val abis = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                            Build.SUPPORTED_ABIS.toList()
                        } else {
                            @Suppress("DEPRECATION")
                            listOf(Build.CPU_ABI)
                        }
                        result.success(abis)
                    }
                    "checkInstallPermission" -> {
                        result.success(canRequestPackageInstalls())
                    }
                    "installApk" -> {
                        val filePath = call.argument<String>("filePath")
                        if (filePath.isNullOrBlank()) {
                            result.error("INVALID_PATH", "APK path is empty", null)
                            return@setMethodCallHandler
                        }
                        result.success(triggerInstallApk(filePath))
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// 处理未知来源权限页返回；返回 true 表示已消费该 requestCode
    fun onActivityResult(requestCode: Int): Boolean {
        if (requestCode != REQUEST_CODE_INSTALL_PERMISSION) return false
        val path = pendingApkPath ?: return true
        if (canRequestPackageInstalls()) {
            pendingApkPath = null
            triggerInstallApk(path)
        }
        return true
    }

    /// 从设置页返回时续装未完成的安装请求
    fun resumePendingInstall() {
        val path = pendingApkPath ?: return
        if (canRequestPackageInstalls()) {
            pendingApkPath = null
            triggerInstallApk(path)
        }
    }

    fun release() {
        pendingApkPath = null
    }

    private fun canRequestPackageInstalls(): Boolean {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            activity.packageManager.canRequestPackageInstalls()
        } else {
            true
        }
    }

    private fun triggerInstallApk(filePath: String): Boolean {
        return try {
            val apkFile = File(filePath)
            if (!apkFile.exists()) return false

            if (!canRequestPackageInstalls()) {
                pendingApkPath = filePath
                val intent = Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${activity.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                activity.startActivityForResult(intent, REQUEST_CODE_INSTALL_PERMISSION)
                return false
            }

            pendingApkPath = null
            val apkUri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                FileProvider.getUriForFile(
                    activity,
                    "${activity.packageName}.fileprovider",
                    apkFile
                )
            } else {
                @Suppress("DEPRECATION")
                Uri.fromFile(apkFile)
            }

            val installIntent = Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(apkUri, "application/vnd.android.package-archive")
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            activity.startActivity(installIntent)
            true
        } catch (e: Exception) {
            e.printStackTrace()
            false
        }
    }

    private companion object {
        const val CHANNEL = "com.debug.yuyin/app_installer"
        const val REQUEST_CODE_INSTALL_PERMISSION = 2002
    }
}
