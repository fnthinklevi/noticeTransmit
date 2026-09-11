package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * FileHasher.sha256Hex 的行为测试（JVM 直测）。
 *
 * 用 RFC/公开已知向量锁定正确性：
 * - "hello" → 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
 * - 空文件  → e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
 * 另覆盖大文件（多缓冲块）流式读取与缺失文件抛错路径。
 * 消费方：应用内更新 N3 传输层校验（computeFileSha256 通道）。
 */
class FileHasherTest {

    @get:Rule
    val temp = TemporaryFolder()

    @Test
    fun sha256OfHello_matchesKnownVector() {
        val file = temp.newFile("hello.bin")
        file.writeBytes("hello".toByteArray(Charsets.UTF_8))
        assertEquals(
            "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824",
            FileHasher.sha256Hex(file.absolutePath)
        )
    }

    @Test
    fun sha256OfEmptyFile_matchesKnownVector() {
        val file = temp.newFile("empty.bin")
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            FileHasher.sha256Hex(file.absolutePath)
        )
    }

    @Test
    fun sha256OfLargeFile_streamsAcrossBufferBoundary() {
        // 8KB 缓冲 + 跨块数据：写入 20001 字节（2 个整块 + 1 字节），与单次 update 结果一致
        val file = temp.newFile("large.bin")
        val bytes = ByteArray(20001) { (it % 251).toByte() }
        file.writeBytes(bytes)

        // 期望值独立计算：单次 digest 全量字节（不走流式路径），再手工转小写十六进制
        val digest = java.security.MessageDigest.getInstance("SHA-256").digest(bytes)
        val expected = digest.joinToString("") { "%02x".format(it) }
        assertEquals(expected, FileHasher.sha256Hex(file.absolutePath))
    }

    @Test
    fun sha256HexOutput_is64LowercaseHex() {
        val file = temp.newFile("any.bin")
        file.writeBytes(ByteArray(1024))
        val hex = FileHasher.sha256Hex(file.absolutePath)
        assertEquals(64, hex.length)
        assertTrue(hex == hex.lowercase())
        assertTrue(Regex("""[0-9a-f]{64}""").matches(hex))
    }

    @Test
    fun missingFile_throwsIOException() {
        try {
            FileHasher.sha256Hex(temp.root.absolutePath + "/no_such_file.apk")
            fail("缺失文件应抛出异常而非返回哈希")
        } catch (expected: Exception) {
            // IOException 或其子类
            assertTrue(expected is java.io.IOException || expected.cause is java.io.IOException)
        }
    }
}
