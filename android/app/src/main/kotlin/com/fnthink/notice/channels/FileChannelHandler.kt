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
                val id = call.argument<String>("downloadId")?.toLongOrNull() ?: -1L
                result.success(activity.installSystemDownload(id))
            }
            else -> return false
        }
        return true
    }
}
