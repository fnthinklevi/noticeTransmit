package com.fnthink.notice

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 幻念推送身份密钥纯层（T26 第三片 A 半）的 JVM 测试。
 *
 * 这一片不需要设备：平台门槛判定、DER 头互换、包裹 blob 的严格解析、"对外形状里不许有私钥"，
 * 四条都能在 JVM 上判生死。KeyStore 真接线（生成/解密/签名）在 3-B，那条要仪器测试。
 */
class FnthinkIdentityCodecTest {

    private fun spki(tail: ByteArray = ByteArray(32) { (it + 1).toByte() }): ByteArray =
        byteArrayOf(0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00) + tail

    private fun pkcs8(tail: ByteArray = ByteArray(32) { (it + 7).toByte() }): ByteArray =
        byteArrayOf(
            0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
            0x04, 0x22, 0x04, 0x20,
        ) + tail

    // ── 平台门槛 ──

    @Test
    fun `门槛边界是 33 —— 32 走包裹，33 走原生`() {
        // 30 是"能生成"，33 才是"能签名"；这条边界钉的是后者。
        assertEquals(33, FnthinkIdentityPolicy.NATIVE_MIN_SDK_VERSION)
        assertEquals(IdentityKeyPlan.KEYSTORE_WRAPPED, FnthinkIdentityPolicy.planFor(32))
        assertEquals(IdentityKeyPlan.NATIVE, FnthinkIdentityPolicy.planFor(33))
        assertEquals(IdentityKeyPlan.NATIVE, FnthinkIdentityPolicy.planFor(34))
        assertEquals(IdentityKeyPlan.KEYSTORE_WRAPPED, FnthinkIdentityPolicy.planFor(24))
    }

    @Test
    fun `keystoreBacked 只在原生路径为真 —— 包裹路径不许蹭这个名字`() {
        assertTrue(FnthinkIdentityPolicy.keystoreBacked(IdentityKeyPlan.NATIVE))
        assertFalse(FnthinkIdentityPolicy.keystoreBacked(IdentityKeyPlan.KEYSTORE_WRAPPED))
    }

    @Test
    fun `契约字符串一致性：30 以下只认 keystoreWrappedSoftwareKey`() {
        assertEquals("keystoreWrappedSoftwareKey", IdentityKeyPlan.KEYSTORE_WRAPPED.contractValue)
        assertTrue(FnthinkIdentityPolicy.isAcceptableBelowNativeSdk("keystoreWrappedSoftwareKey"))
        // 有人把契约改成"软件明文"时，这里必须是 false（Kotlin 侧随之拒绝工作）
        assertFalse(FnthinkIdentityPolicy.isAcceptableBelowNativeSdk("softwarePlaintext"))
        assertFalse(FnthinkIdentityPolicy.isAcceptableBelowNativeSdk(""))
    }

    // ── DER 头与裸字节的互换 ──

    @Test
    fun `SPKI 拆出裸公钥，再包回去必须逐字节相同`() {
        val raw = Ed25519Encoding.rawPublicFromSpki(spki())
        assertEquals(32, raw.size)
        assertArrayEquals(spki(), Ed25519Encoding.spkiFromRawPublic(raw))
    }

    @Test
    fun `PKCS8 拆出裸私钥种子，再包回去必须逐字节相同`() {
        val raw = Ed25519Encoding.rawPrivateFromPkcs8(pkcs8())
        assertEquals(32, raw.size)
        assertArrayEquals(pkcs8(), Ed25519Encoding.pkcs8FromRawPrivate(raw))
    }

    @Test
    fun `头不对的编码直接抛 —— 不许盲切尾部 32 字节`() {
        // 一把 P-256 的 SPKI 长度也可能凑成 44 字节；切尾巴会得到一个"看着像"的公钥，
        // 之后每条推送都验签失败，而现场看起来一切正常。
        val foreign = ByteArray(44) { (it % 251).toByte() }
        try {
            Ed25519Encoding.rawPublicFromSpki(foreign)
            throw AssertionError("应抛：DER 头不符")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!, e.message!!.contains("DER 头"))
        }
    }

    @Test
    fun `长度不对的编码直接抛`() {
        try {
            Ed25519Encoding.rawPublicFromSpki(spki().copyOfRange(0, 40))
            throw AssertionError("应抛：长度")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("长度"))
        }
        try {
            Ed25519Encoding.spkiFromRawPublic(ByteArray(31))
            throw AssertionError("应抛：裸公钥长度")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("32"))
        }
    }

    // ── 包裹 blob ──

    @Test
    fun `包裹 blob 往返`() {
        val iv = ByteArray(12) { (it + 3).toByte() }
        val ct = ByteArray(48) { (it * 5).toByte() }
        val sealed = WrappedIdentityBlob.decode(WrappedIdentityBlob.encode(iv, ct))
        assertArrayEquals(iv, sealed.iv)
        assertArrayEquals(ct, sealed.ciphertext)
    }

    @Test
    fun `截断的 blob 拒绝，不试着解一下`() {
        val good = WrappedIdentityBlob.encode(ByteArray(12), ByteArray(48))
        for (cut in listOf(1, 5, 12, 16, 40, good.size - 1)) {
            try {
                WrappedIdentityBlob.decode(good.copyOfRange(0, cut))
                throw AssertionError("应抛：截断到 $cut")
            } catch (e: IllegalArgumentException) {
                // 允许两种点名：头不对（切进 MAGIC 里）与长度不对
                val msg = e.message!!
                assertTrue(msg, msg.contains("头不是") || msg.contains("长度") || msg.contains("太短"))
            }
        }
    }

    @Test
    fun `别人的 blob 与跨版本 blob 都拒绝`() {
        val foreign = "XXXX".toByteArray() + byteArrayOf(1) + ByteArray(12) + ByteArray(48)
        try {
            WrappedIdentityBlob.decode(foreign)
            throw AssertionError("应抛：不是本功能的包裹私钥")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("头不是"))
        }
        val v2 = WrappedIdentityBlob.encode(ByteArray(12), ByteArray(48))
        v2[4] = 2
        try {
            WrappedIdentityBlob.decode(v2)
            throw AssertionError("应抛：跨版本必须走迁移")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("版本"))
        }
    }

    @Test
    fun `iv 与密文长度不对不许被拼成 blob`() {
        try {
            WrappedIdentityBlob.encode(ByteArray(11), ByteArray(48))
            throw AssertionError("应抛：iv 长度")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("iv"))
        }
        try {
            WrappedIdentityBlob.encode(ByteArray(12), ByteArray(47))
            throw AssertionError("应抛：密文长度")
        } catch (e: IllegalArgumentException) {
            assertTrue(e.message!!.contains("密文"))
        }
        assertEquals(48, WrappedIdentityBlob.CIPHERTEXT_BYTES)
    }

    @Test
    fun `toString 只报字节数，不把包裹材料写进日志`() {
        val iv = ByteArray(12) { 1 }
        val ct = ByteArray(48) { 2 }
        val sealed = WrappedIdentityBlob.Sealed(iv, ct)
        val text = sealed.toString()
        assertFalse("iv 被原样带进 toString", text.contains(iv.contentToString()))
        assertFalse("密文被原样带进 toString", text.contains(ct.contentToString()))
        assertTrue("应只报长度：$text", text.contains("12B") && text.contains("48B"))
        val identity = FnthinkIdentity("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=", IdentityKeyPlan.NATIVE)
        assertFalse(identity.toString().contains("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="))
    }

    /**
     * 结构守卫：`FnthinkIdentity` 是会被塞进日志、MethodChannel 返回值、甚至界面 ViewModel 的类型，
     * 一旦哪天有人顺手加一个 `privateKey` 字段，泄露就从"可能"变成"默认"。
     */
    @Test
    fun `对外身份卡片里不许存在任何私钥字段`() {
        val banned = Regex("private|seed|secret|keymaterial", RegexOption.IGNORE_CASE)
        val offenders = FnthinkIdentity::class.java.declaredFields
            .filter { banned.containsMatchIn(it.name) || it.type == ByteArray::class.java }
            .map { it.name + ":" + it.type.simpleName }
        assertTrue("发现私钥字样或裸字节字段：$offenders", offenders.isEmpty())
    }
}
