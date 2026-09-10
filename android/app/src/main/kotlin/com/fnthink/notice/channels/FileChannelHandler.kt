package com.fnthink.notice.channels

import com.fnthink.notice.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 文件与下载域：下载目录路径、文件选择器导出（saveFile）、
 * 系统下载器（DownloadManager）下载更新 APK、进度轮询、已下载 APK 路径与安装。
 */
internal class FileChannelHandler(activity: MainActivity) : ChannelHandler(activity) {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "getDownloadDirectory" -> {
                result.success(activity.getDownloadDirectory())
            }
            "saveFile" -> {
                val fileName = call.argument<String>("fileName") ?: "export.json"
                val content = call.argument<String>("content") ?: ""
                activity.saveFileWithPicker(fileName, content, result)
            }
            "pickArchiveDirectory" -> {
                // P1：推送历史自动归档目录选择（SAF + 持久化授权）
                activity.pickArchiveDirectory(result)
            }
            "getArchiveDirectory" -> {
                result.success(activity.getPersistedArchiveDir())
            }
            "clearArchiveDirectory" -> {
                activity.clearArchiveDir()
                result.success(true)
            }
            "writeArchiveFile" -> {
                val fileName = call.argument<String>("fileName") ?: ""
                val content = call.argument<String>("content") ?: ""
                result.success(activity.writeArchiveFile(fileName, content))
            }
            "startSystemDownload" -> {
                // 使用系统下载器（DownloadManager）下载更新 APK，无需存储权限
                val url = call.argument<String>("url") ?: ""
                val fileName = call.argument<String>("fileName") ?: "app_update.apk"
                val title = call.argument<String>("title") ?: "通知推送助手"
                result.success(activity.startSystemDownload(url, fileName, title))
            }
            "getSystemDownloadProgress" -> {
                val id = call.argument<String>("downloadId")?.toLongOrNull() ?: -1L
                result.success(activity.querySystemDownloadProgress(id))
            }
            "getDownloadedApkPath" -> {
                val id = call.argument<String>("downloadId")?.toLongOrNull() ?: -1L
                result.success(activity.getDownloadedApkPath(id))
            }
            "installSystemDownload" -> {
                // 返回 (ok, detail)：detail 为失败原因的 I18n 双语文案，
                // Dart 侧透传到 UI，避免英文用户看到硬编码中文
                val id = call.argument<String>("downloadId")?.toLongOrNull() ?: -1L
                val (ok, detail) = activity.installSystemDownload(id)
                result.success(mapOf("ok" to ok, "detail" to detail))
            }
            "verifyApkSignature" -> {
                // P0 安全加固：下载包签名必须与当前应用签名一致（可信根=本机签名，
                // 独立于分发服务器），不一致则 Dart 侧阻止安装并删除安装包
                val filePath = call.argument<String>("filePath") ?: ""
                val (valid, detail) = activity.verifyApkSignature(filePath)
                result.success(mapOf("valid" to valid, "detail" to detail))
            }
            else -> return false
        }
        return true
    }
}
