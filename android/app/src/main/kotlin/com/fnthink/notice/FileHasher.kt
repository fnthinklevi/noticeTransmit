package com.fnthink.notice

import java.io.File
import java.io.FileInputStream
import java.security.MessageDigest

/**
 * 文件哈希工具（纯 JVM，可单测）。
 *
 * 用途：应用内更新（N3）的 sha256 传输层校验——version.json 下发各架构安装包的
 * 期望 sha256，下载完成后 Dart 侧经 `computeFileSha256` 通道调用本类计算实际值比对。
 * 作为签名校验（可信根）之外的**附加层**，防 CDN 传输损坏。
 *
 * 实现：流式读取（8KB 缓冲），70MB 级 APK 不会占用过多内存；
 * 输出为 64 位小写十六进制字符串（与 version.json 下发格式一致）。
 */
object FileHasher {
    /** 小写十六进制字符表 */
    private val HEX_CHARS = "0123456789abcdef".toCharArray()

    /**
     * 计算 [path] 指向文件的 SHA-256，返回 64 位小写十六进制字符串。
     * 文件不存在或不可读时抛出 [java.io.IOException]。
     */
    fun sha256Hex(path: String): String {
        val digest = MessageDigest.getInstance("SHA-256")
        FileInputStream(File(path)).use { input ->
            val buffer = ByteArray(8192)
            while (true) {
                val read = input.read(buffer)
                if (read < 0) break
                digest.update(buffer, 0, read)
            }
        }
        return toHex(digest.digest())
    }

    private fun toHex(bytes: ByteArray): String {
        val out = CharArray(bytes.size * 2)
        var i = 0
        for (b in bytes) {
            val v = b.toInt() and 0xFF
            out[i++] = HEX_CHARS[v ushr 4]
            out[i++] = HEX_CHARS[v and 0x0F]
        }
        return String(out)
    }
}
