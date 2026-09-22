package com.fnthink.notice.channels

import com.fnthink.notice.FileHasher
import com.fnthink.notice.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

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
                // 整份归档经 SAF 写出（可达数 MB），不得占用平台线程
                ioScope.launch {
                    postSuccess(result, activity.writeArchiveFile(fileName, content))
                }
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
                // 内含「暂存副本全量复制 + 签名校验」，是本域最重的一步
                ioScope.launch {
                    val (ok, detail) = activity.installSystemDownload(id)
                    postSuccess(result, mapOf("ok" to ok, "detail" to detail))
                }
            }
            "verifyApkSignature" -> {
                // P0 安全加固：下载包签名必须与当前应用签名一致（可信根=本机签名，
                // 独立于分发服务器），不一致则 Dart 侧阻止安装并删除安装包
                val filePath = call.argument<String>("filePath") ?: ""
                ioScope.launch {
                    val (valid, detail) = activity.verifyApkSignature(filePath)
                    postSuccess(result, mapOf("valid" to valid, "detail" to detail))
                }
            }
            "computeFileSha256" -> {
                // N3 传输层校验：计算安装包 sha256（64 位小写十六进制），
                // 与 version.json 下发的期望值比对；文件缺失/不可读时抛 IOException，
                // 由 Dart 侧按「通道异常跳过 sha256、签名校验兜底」策略处理。
                // 30-100MB 整包哈希在平台线程会让 UI 冻结数十秒，故下沉 IO 并以 error 回传
                val filePath = call.argument<String>("filePath") ?: ""
                ioScope.launch {
                    try {
                        postSuccess(result, FileHasher.sha256Hex(filePath))
                    } catch (e: Exception) {
                        postError(result, "sha256_failed", e.message ?: "哈希计算失败")
                    }
                }
            }
            else -> return false
        }
        return true
    }
}
