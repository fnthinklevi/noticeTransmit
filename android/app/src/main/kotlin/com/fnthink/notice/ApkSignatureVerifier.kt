package com.fnthink.notice

import android.content.Context
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.content.pm.Signature
import android.os.Build
import android.util.Log
import java.io.File
import java.security.MessageDigest

/**
 * 应用内更新包的完整性校验（P0 安全加固）。
 *
 * **可信根 = 本机已安装应用的签名证书**，独立于任何分发服务器：
 * 无论下载源（CDN / 镜像 / GitHub）被入侵、投毒还是被劫持，
 * 非本项目签名密钥签署的安装包一律判定无效。
 * （sha256 存在 version.json 里无法防御服务端被控时 hash 与 APK 被同时篡改。）
 *
 * 防御点：
 * 1. 签名一致性：归档包签名证书集合必须与当前应用**完全相同**
 * 2. 版本回滚防护：归档包 versionCode 不得低于当前版本
 *    —— 否则服务端被控时可投放**同签名的旧版** APK，把用户回滚到有漏洞的版本
 * 3. fail-closed：任何解析/读取异常一律判定不通过，绝不降级放行
 *
 * 调用方必须校验**即将安装的同一份文件**（见 MainActivity.installSystemDownload），
 * 否则存在校验后被替换的 TOCTOU 窗口。
 */
object ApkSignatureVerifier {
    private const val TAG = "ApkSignatureVerifier"

    data class VerifyResult(val valid: Boolean, val detail: String)

    /** SHA-256 摘要的十六进制（小写，无分隔符） */
    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes)
            .joinToString("") { "%02x".format(it) }

    private fun signingFlags(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P)
            PackageManager.GET_SIGNING_CERTIFICATES else PackageManager.GET_SIGNATURES

    /** 从 PackageInfo 提取签名证书指纹集合；无签名信息返回 null */
    fun extractSigningFingerprints(info: PackageInfo?): Set<String>? {
        if (info == null) return null
        val sigs: List<Signature> = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            val si = info.signingInfo ?: return null
            if (si.hasMultipleSigners()) si.apkContentsSigners.toList()
            else si.signingCertificateHistory.toList()
        } else {
            @Suppress("DEPRECATION")
            info.signatures?.toList() ?: return null
        }
        if (sigs.isEmpty()) return null
        return sigs.map { sha256Hex(it.toByteArray()) }.toSet()
    }

    private fun versionCodeOf(info: PackageInfo): Long =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) info.longVersionCode
        else info.versionCode.toLong()

    /**
     * 纯逻辑决策（不依赖 Android 框架，便于单元测试）：
     * 依次判定当前/归档签名可读性、签名一致性、版本回滚。
     */
    fun decide(
        current: Set<String>?,
        archive: Set<String>?,
        archiveCode: Long,
        currentCode: Long
    ): VerifyResult {
        current ?: return VerifyResult(false, I18n.updateSigReadCurrentFail())
        archive ?: return VerifyResult(false, I18n.updateSigParseFail())
        if (current != archive) {
            Log.e(TAG, "更新包签名不一致，已阻止安装")
            return VerifyResult(false, I18n.updateSigMismatch())
        }
        if (archiveCode < currentCode) {
            Log.e(TAG, "更新包版本低于当前版本（$archiveCode < $currentCode），已阻止降级安装")
            return VerifyResult(false, I18n.updateSigDowngradeBlocked())
        }
        Log.i(TAG, "更新包校验通过（签名一致，versionCode=$archiveCode >= $currentCode）")
        return VerifyResult(true, "")
    }

    /**
     * 校验 APK 文件：签名一致且非降级版本。
     * @param apkPath 必须是即将被安装的同一份文件路径
     */
    fun verify(context: Context, apkPath: String): VerifyResult {
        if (apkPath.isEmpty()) return VerifyResult(false, I18n.updateSigFileMissing())
        val file = File(apkPath)
        if (!file.exists() || file.length() <= 0L) {
            return VerifyResult(false, I18n.updateSigFileMissing())
        }

        val pm = context.packageManager
        val flags = signingFlags()

        val currentInfo = try {
            pm.getPackageInfo(context.packageName, flags)
        } catch (e: Exception) {
            Log.e(TAG, "读取当前应用签名失败", e)
            null
        }
        val archiveInfo = try {
            pm.getPackageArchiveInfo(apkPath, flags)
        } catch (e: Exception) {
            Log.e(TAG, "解析安装包签名失败: $apkPath", e)
            null
        }

        return decide(
            current = extractSigningFingerprints(currentInfo),
            archive = extractSigningFingerprints(archiveInfo),
            archiveCode = archiveInfo?.let { versionCodeOf(it) } ?: Long.MIN_VALUE,
            currentCode = currentInfo?.let { versionCodeOf(it) } ?: Long.MAX_VALUE
        )
    }
}
