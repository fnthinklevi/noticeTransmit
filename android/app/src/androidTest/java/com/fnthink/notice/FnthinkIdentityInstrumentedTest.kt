package com.fnthink.notice

import android.content.Context
import android.os.Build
import android.util.Base64
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.security.GeneralSecurityException
import java.security.KeyStore

/**
 * 幻念推送身份密钥的设备侧仪表测试（T26 第三片 B 半）。
 *
 * 这些用例是"探测换来的事实"的存放处 —— 三轮探测得到的结论（KeyStore 建 Ed25519 要走
 * `EC + ECGenParameterSpec("ed25519")`、签名要用 `Signature("Ed25519")` 而不是
 * `("Ed25519","AndroidKeyStore")`、`getEntry()` 读不回 Ed25519 条目）都落在这里，
 * 平台哪天变了，红的会是这条测试而不是线上的一次投递失败。
 *
 * 跑法：`./gradlew :app:connectedDebugAndroidTest`（模拟器或真机；本项目用 ci_api34_pixel6）。
 */
@RunWith(AndroidJUnit4::class)
class FnthinkIdentityInstrumentedTest {

    private lateinit var context: Context

    private fun pubFile(plan: IdentityKeyPlan): File =
        File(context.noBackupFilesDir, "fnthink_identity.${if (plan == IdentityKeyPlan.NATIVE) "native" else "wrapped"}.pub")

    private val keyFile get() = File(context.noBackupFilesDir, "fnthink_identity.wrapped.key")

    @Before
    fun wipe() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        listOf(pubFile(IdentityKeyPlan.NATIVE), pubFile(IdentityKeyPlan.KEYSTORE_WRAPPED), keyFile).forEach {
            it.delete()
        }
        val ks = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        ks.deleteEntry("fnthink-identity-ed25519")
        ks.deleteEntry("fnthink-identity-wrap-aes256")
    }

    // ── 包裹路径（API 24–32 的主路，也是 33+ 上原生不可用时的退路） ──

    @Test
    fun wrappedIdentity_isStableAndSignsVerifiably() {
        val first = FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        val again = FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        assertEquals("同一路径两次取身份必须同值（换了就是换身份）", first.publicKeyBase64, again.publicKeyBase64)
        assertEquals(IdentityKeyPlan.KEYSTORE_WRAPPED, again.plan)
        assertFalse("包裹路径不许自称 keystoreBacked", again.keystoreBacked)

        val message = "温度告警：机箱 63℃".toByteArray()
        val signature = FnthinkIdentityStore.signWith(context, first, message)
        assertEquals("Ed25519 签名固定 64 字节", 64, signature.size)
        assertTrue(
            "独立实现（eddsa 库）必须验得过",
            FnthinkIdentityStore.verify(first.publicKeyBase64, message, signature),
        )
        assertFalse(
            "改一个字就必须验不过 —— 否则上面那条 true 是假的",
            FnthinkIdentityStore.verify(first.publicKeyBase64, "温度告警：机箱 64℃".toByteArray(), signature),
        )
    }

    @Test
    fun wrappedPrivateKeyOnDisk_isOnlyTheSealedBlob() {
        FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        assertTrue("私钥文件必须落在 noBackupFilesDir（否则会被 Auto Backup 带走）", keyFile.exists())
        val bytes = keyFile.readBytes()
        assertEquals("包裹格式长度 = 4 魔数 + 1 版本 + 12 iv + 48 密文(含 tag)", 65, bytes.size)
        assertEquals("FTWK", String(bytes.copyOfRange(0, 4), Charsets.US_ASCII))
        val text = String(bytes, Charsets.ISO_8859_1)
        val pub = pubFile(IdentityKeyPlan.KEYSTORE_WRAPPED).readText()
        assertFalse("落盘内容不许含公钥（更不许含种子）", text.contains(pub.take(12)))
    }

    @Test
    fun wrapped_rebuildsPublicKey_fromPrivateKeyWithoutChangingIdentity() {
        val first = FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        pubFile(IdentityKeyPlan.KEYSTORE_WRAPPED).delete()
        val restored = FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        assertEquals("公钥缓存丢了要从私钥重算，**不许另生成一把**", first.publicKeyBase64, restored.publicKeyBase64)
    }

    @Test
    fun wrapped_missingPrivateKeyWithPublicKeyPresent_failsInsteadOfSilentlyReseeding() {
        FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        keyFile.delete()
        try {
            FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
            fail("私钥没了、公钥还在：静默新建会让对端白名单里留着一把没人能签的公钥")
        } catch (e: GeneralSecurityException) {
            assertTrue(e.message!!, e.message!!.contains("重置身份"))
        }
        assertFalse("state() 必须把这判成不一致，UI 才有机会问用户",
            FnthinkIdentityStore.state(context)["consistent"] as Boolean)
    }

    @Test
    fun existingIdentityWinsOverPreferredPlan() {
        val wrapped = FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        assertEquals(IdentityKeyPlan.KEYSTORE_WRAPPED, FnthinkIdentityStore.existingPlan(context))
        assumeTrue("只有在偏好原生路径的设备上，这条才有内容", Build.VERSION.SDK_INT >= 33)
        assertEquals("已有身份优先于当前偏好：否则原生一抽风就换身份", wrapped.publicKeyBase64,
            FnthinkIdentityStore.identity(context).publicKeyBase64)
    }

    // ── 原生路径（探测换来的写法就钉在这几条里） ──

    @Test
    fun nativeIdentity_signsAndCrossVerifies() {
        assumeTrue("KeyStore Ed25519 只在 API 33+ 上试", Build.VERSION.SDK_INT >= 33)
        val identity = FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.NATIVE)
        assertEquals(IdentityKeyPlan.NATIVE, identity.plan)
        assertTrue("原生路径才配得上 keystoreBacked", identity.keystoreBacked)
        assertEquals("裸公钥解码后是 32 字节（base64 文本 44 字符）", 32,
            Base64.decode(identity.publicKeyBase64, Base64.NO_WRAP).size)
        assertEquals(44, identity.publicKeyBase64.length)

        val message = "设备状态：充电中 / wifi".toByteArray()
        val signature = FnthinkIdentityStore.signWith(context, identity, message)
        assertTrue("KeyStore 签的必须被另一套实现验过", FnthinkIdentityStore.verify(identity.publicKeyBase64, message, signature))
        assertFalse("同一条签名换报文必须验不过",
            FnthinkIdentityStore.verify(identity.publicKeyBase64, "别的报文".toByteArray(), signature))
    }

    @Test
    fun nativeAndWrappedIdentitiesAreDifferentKeys() {
        assumeTrue(Build.VERSION.SDK_INT >= 33)
        val nativeId = FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.NATIVE)
        val wrappedId = FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        assertNotEquals(nativeId.publicKeyBase64, wrappedId.publicKeyBase64)
        val message = "交叉检查".toByteArray()
        val nativeSig = FnthinkIdentityStore.signWith(context, nativeId, message)
        val wrappedSig = FnthinkIdentityStore.signWith(context, wrappedId, message)
        assertFalse("两把钥匙的签名不许互认",
            FnthinkIdentityStore.verify(wrappedId.publicKeyBase64, message, nativeSig))
        assertTrue(FnthinkIdentityStore.verify(wrappedId.publicKeyBase64, message, wrappedSig))
    }

    @Test
    fun peekDoesNotCreateAnIdentity() {
        assumeTrue(Build.VERSION.SDK_INT >= 33)
        // 页面首帧会调它：不能因为"看了一眼设置页"就生成了身份
        assertEquals(null, FnthinkIdentityStore.peekPublicKeyBase64(context))
        FnthinkIdentityStore.identityOn(context, IdentityKeyPlan.NATIVE)
        assertNotEquals(null, FnthinkIdentityStore.peekPublicKeyBase64(context))
    }
}
