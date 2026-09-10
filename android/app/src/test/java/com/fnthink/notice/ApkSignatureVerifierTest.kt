package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * [ApkSignatureVerifier] 单元测试（安全关键路径：fail-closed 逻辑）。
 *
 * 覆盖：
 * - [ApkSignatureVerifier.sha256Hex] 纯函数正确性（已知向量）
 * - [ApkSignatureVerifier.extractSigningFingerprints] 空输入
 * - [ApkSignatureVerifier.decide] 完整决策矩阵：
 *   签名不可读 / 签名不一致 / **版本降级** / 同版本重装 / 正常升级
 *
 * 需要真实 Context 的 [ApkSignatureVerifier.verify] 由仪表测试覆盖
 * （见 androidTest/.../ApkSignatureVerifierInstrumentedTest.kt）。
 */
class ApkSignatureVerifierTest {

    @Test
    fun sha256Hex_emptyInput() {
        assertEquals(
            "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
            ApkSignatureVerifier.sha256Hex(ByteArray(0))
        )
    }

    @Test
    fun sha256Hex_knownVectorAbc() {
        assertEquals(
            "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad",
            ApkSignatureVerifier.sha256Hex("abc".toByteArray())
        )
    }

    @Test
    fun sha256Hex_isLowercaseHex64Chars() {
        val hex = ApkSignatureVerifier.sha256Hex("notice".toByteArray())
        assertEquals(64, hex.length)
        assertTrue(hex.all { it in '0'..'9' || it in 'a'..'f' })
    }

    @Test
    fun extractSigningFingerprints_nullInput() {
        assertNull(ApkSignatureVerifier.extractSigningFingerprints(null))
    }

    @Test
    fun decide_failsClosedWhenCurrentSignatureUnreadable() {
        val r = ApkSignatureVerifier.decide(
            current = null, archive = setOf("aa"), archiveCode = 200, currentCode = 100
        )
        assertFalse(r.valid)
        assertTrue(r.detail.isNotEmpty())
    }

    @Test
    fun decide_failsClosedWhenArchiveSignatureUnreadable() {
        val r = ApkSignatureVerifier.decide(
            current = setOf("aa"), archive = null, archiveCode = 200, currentCode = 100
        )
        assertFalse(r.valid)
        assertTrue(r.detail.isNotEmpty())
    }

    @Test
    fun decide_rejectsSignatureMismatch() {
        val r = ApkSignatureVerifier.decide(
            current = setOf("aa"), archive = setOf("bb"), archiveCode = 200, currentCode = 100
        )
        assertFalse("签名不一致必须拒绝（即使版本更新）", r.valid)
    }

    @Test
    fun decide_rejectsDowngradeEvenWithSameSignature() {
        // 同签名的旧版本同样危险：服务端被控时可把用户回滚到有漏洞的版本
        val r = ApkSignatureVerifier.decide(
            current = setOf("aa"), archive = setOf("aa"), archiveCode = 99, currentCode = 100
        )
        assertFalse("版本降级必须拒绝（即使签名一致）", r.valid)
    }

    @Test
    fun decide_rejectsPartialSignatureOverlap() {
        // 多签名场景：归档包签名是当前应用签名的真子集也必须拒绝
        val r = ApkSignatureVerifier.decide(
            current = setOf("aa", "bb"),
            archive = setOf("aa"),
            archiveCode = 200,
            currentCode = 100
        )
        assertFalse(r.valid)
    }

    @Test
    fun decide_acceptsUpgradeWithSameSignature() {
        val r = ApkSignatureVerifier.decide(
            current = setOf("aa"), archive = setOf("aa"), archiveCode = 101, currentCode = 100
        )
        assertTrue(r.valid)
    }

    @Test
    fun decide_acceptsSameVersionReinstall() {
        val r = ApkSignatureVerifier.decide(
            current = setOf("aa"), archive = setOf("aa"), archiveCode = 100, currentCode = 100
        )
        assertTrue("同版本重装应允许（用 >= 比较）", r.valid)
    }
}
