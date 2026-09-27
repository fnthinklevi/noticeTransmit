package com.fnthink.notice

import android.content.Context
import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.util.Log
import net.i2p.crypto.eddsa.EdDSAEngine
import net.i2p.crypto.eddsa.EdDSAPrivateKey
import net.i2p.crypto.eddsa.EdDSAPublicKey
import net.i2p.crypto.eddsa.spec.EdDSANamedCurveTable
import net.i2p.crypto.eddsa.spec.EdDSAPrivateKeySpec
import net.i2p.crypto.eddsa.spec.EdDSAPublicKeySpec
import java.io.File
import java.security.GeneralSecurityException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.MessageDigest
import java.security.PrivateKey
import java.security.SecureRandom
import java.security.Signature
import java.security.spec.ECGenParameterSpec
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * 幻念推送身份密钥的设备侧实现（T26 第三片 B 半）。两条路径：
 *
 *  - **原生**（[IdentityKeyPlan.NATIVE]，SDK ≥ [FnthinkIdentityPolicy.NATIVE_MIN_SDK_VERSION] 才优先尝试）：
 *    KeyStore 里的 Ed25519，私钥本体从不离开 KeyStore。
 *  - **包裹**（[IdentityKeyPlan.KEYSTORE_WRAPPED]，SDK 24–32 或原生真跑不通时）：软件生成 32 字节种子，
 *    用 KeyStore 里一把不可导出的 AES-256-GCM 密钥包裹后落盘，运行期解到内存、用完即弃。
 *
 * ⚠ **下面这些写法来自设备探测，不是文档**（`FnthinkIdentityInstrumentedTest` 逐条钉住）：
 *  - 建 KeyStore Ed25519 走 `KeyPairGenerator("EC", AndroidKeyStore)` + `ECGenParameterSpec("ed25519")`。
 *    网上常见的 `EdECGenParameterSpec` / `EdECParameterSpec` 在本机 android.jar（33–37）与 API 34 镜像上
 *    **都不存在** —— 照抄文档会得到一个连编译都过不去的实现；
 *  - 签名用 `Signature.getInstance("Ed25519")`（平台把它路由到 `AndroidKeyStoreBCWorkaround`）；
 *    `Signature.getInstance("Ed25519", "AndroidKeyStore")` 反而 **no such algorithm**；
 *  - AES 包裹要用 `Cipher.getInstance("AES/GCM/NoPadding")`（**不指定 provider**）：
 *    KeyStore 密钥由密钥本身决定谁来做运算，写成 `("AES/GCM/NoPadding", "AndroidKeyStore")`
 *    会直接 `NoSuchAlgorithmException: Provider AndroidKeyStore does not provide AES/GCM/NoPadding`；
 *  - `KeyStore.getEntry(alias, null)` 读 Ed25519 条目会抛
 *    "private key algorithm does not match algorithm of public key in end entity certificate" ——
 *    所以取私钥走 `getKey()`，公钥在**建钥当场**从 KeyPair 上取并缓存到文件（公钥本就可公开）。
 *
 * 两条不变量：① **绝不在私钥不见时补一把新身份** —— 那会让对端白名单里留着一把没人能签的公钥，
 * 而本机看着一切正常，表现成"对方永远收不到我的推送"；② 落盘的只有密文与公钥，种子只存在于内存。
 */
object FnthinkIdentityStore {

    private const val PROVIDER = "AndroidKeyStore"
    private const val NATIVE_ALIAS = "fnthink-identity-ed25519"
    private const val WRAP_ALIAS = "fnthink-identity-wrap-aes256"
    private const val PUB_FILE_PREFIX = "fnthink_identity."
    private const val KEY_FILE = "fnthink_identity.wrapped.key"
    private const val GCM_TAG_BITS = 128
    private const val TAG = "FnthinkIdentity"

    /** 身份文件放 `noBackupFilesDir`：Auto Backup 与手动备份都不该带走它（T59 的边界）。 */
    private fun file(context: Context, name: String): File = File(context.noBackupFilesDir, name)

    /** 两条路径各一份公钥缓存。共用一个文件会让"降级"看起来像"换了身份"，两边互相覆盖。 */
    private fun pubFile(context: Context, plan: IdentityKeyPlan): File =
        file(context, "$PUB_FILE_PREFIX${plan.fileNameTag()}.pub")

    private fun IdentityKeyPlan.fileNameTag(): String = when (this) {
        IdentityKeyPlan.NATIVE -> "native"
        IdentityKeyPlan.KEYSTORE_WRAPPED -> "wrapped"
    }

    /**
     * 本机**已经存在**的身份走的是哪条路（没有则 null）。
     *
     * 为什么优先看它：`identity()` 若只看当前系统版本，会在"原生路径临时抽风"的那一刻
     * 悄悄顶上一个新身份 —— 对端白名单里那把公钥当场作废，而用户什么提示都没收到。
     */
    @Synchronized
    fun existingPlan(context: Context): IdentityKeyPlan? = when {
        runCatching { keyStore().containsAlias(NATIVE_ALIAS) }.getOrDefault(false) ->
            IdentityKeyPlan.NATIVE

        file(context, KEY_FILE).exists() -> IdentityKeyPlan.KEYSTORE_WRAPPED
        else -> null
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(PROVIDER).apply { load(null) }

    /** 本机的优先路径。⚠ 那**只是优先级**：原生真不可用时会降级，并在返回值里如实带上走了哪条。 */
    fun preferredPlan(): IdentityKeyPlan = FnthinkIdentityPolicy.planFor(Build.VERSION.SDK_INT)

    @Synchronized
    fun identity(context: Context): FnthinkIdentity = identityOn(context, existingPlan(context) ?: preferredPlan())

    /** 显式指定走哪条路（仪器测试要两条都钉；生产代码走 [identity]）。 */
    @Synchronized
    fun identityOn(context: Context, plan: IdentityKeyPlan): FnthinkIdentity = when (plan) {
        IdentityKeyPlan.NATIVE ->
            FnthinkIdentity(nativePublicKeyBase64(context), IdentityKeyPlan.NATIVE)

        IdentityKeyPlan.KEYSTORE_WRAPPED ->
            FnthinkIdentity(wrappedPublicKeyBase64(context), IdentityKeyPlan.KEYSTORE_WRAPPED)
    }

    /** 只报告、不建钥：页面首帧用它，避免"打开设置页就悄悄生成了一个身份"。 */
    @Synchronized
    fun peekPublicKeyBase64(context: Context): String? =
        existingPlan(context)?.let { plan -> pubFile(context, plan).takeIf { it.exists() }?.readText()?.trim() }

    @Synchronized
    fun sign(context: Context, message: ByteArray): ByteArray =
        signWith(context, identity(context), message)

    @Synchronized
    fun signWith(context: Context, identity: FnthinkIdentity, message: ByteArray): ByteArray =
        when (identity.plan) {
            IdentityKeyPlan.NATIVE -> nativeSign(nativePrivateKey(), identity, message)
            IdentityKeyPlan.KEYSTORE_WRAPPED -> wrappedSign(context, message)
        }

    /**
     * 用**另一套实现**（eddsa 库）验签。
     *
     * 这是"证明公钥取对了、签名格式也对"的唯一手段：自签自验用的同一套代码，编码错了会一起错。
     * 仪器测试里是"原生签、软件验"，两边各自没错才对得上。
     */
    fun verify(publicKeyBase64: String, message: ByteArray, signature: ByteArray): Boolean =
        try {
            val spec = EdDSANamedCurveTable.getByName(EdDSANamedCurveTable.ED_25519)
            val engine = EdDSAEngine(MessageDigest.getInstance(spec.hashAlgorithm))
            engine.initVerify(EdDSAPublicKey(EdDSAPublicKeySpec(rawOf(publicKeyBase64), spec)))
            engine.update(message)
            engine.verify(signature)
        } catch (e: Exception) {
            false
        }

    // ── 原生路径 ──

    private fun nativePrivateKey(): PrivateKey =
        keyStore().getKey(NATIVE_ALIAS, null) as? PrivateKey
            ?: throw GeneralSecurityException("KeyStore 里没有身份私钥（$NATIVE_ALIAS）")

    private fun nativePublicKeyBase64(context: Context): String {
        val pubFile = pubFile(context, IdentityKeyPlan.NATIVE)
        if (keyStore().containsAlias(NATIVE_ALIAS)) {
            if (pubFile.exists()) return pubFile.readText().trim()
            val fromCert = keyStore().getCertificate(NATIVE_ALIAS)?.publicKey?.encoded
                ?: throw GeneralSecurityException(
                    "私钥在、公钥缓存丢了且证书读不回来：要用户显式重置身份（T31），不能悄悄换一把",
                )
            return writePub(context, IdentityKeyPlan.NATIVE, fromCert)
        }
        val kpg = KeyPairGenerator.getInstance(KeyProperties.KEY_ALGORITHM_EC, PROVIDER)
        kpg.initialize(
            KeyGenParameterSpec
                .Builder(NATIVE_ALIAS, KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY)
                .setAlgorithmParameterSpec(ECGenParameterSpec("ed25519"))
                // EdDSA 是纯签名：摘要在曲线内部做。让 KeyStore 再摘要一次，会得到没人验得过的签名。
                .setDigests(KeyProperties.DIGEST_NONE)
                .build(),
        )
        return writePub(context, IdentityKeyPlan.NATIVE, kpg.generateKeyPair().public.encoded)
    }

    private fun writePub(
        context: Context,
        plan: IdentityKeyPlan,
        subjectPublicKeyInfo: ByteArray,
    ): String {
        val text = encode(Ed25519Encoding.rawPublicFromSpki(subjectPublicKeyInfo))
        pubFile(context, plan).writeText(text)
        return text
    }

    private fun nativeSign(
        privateKey: PrivateKey,
        identity: FnthinkIdentity,
        message: ByteArray,
    ): ByteArray {
        val sig = Signature.getInstance("Ed25519")
        sig.initSign(privateKey)
        sig.update(message)
        val out = sig.sign()
        // 自证一次：平台偶尔会返回"形状对但没人认"的字节。让它在这里红，
        // 比让它变成线上第 N 次投递失败之后再回头查便宜得多。
        if (!verify(identity.publicKeyBase64, message, out)) {
            throw GeneralSecurityException("原生签名未通过独立实现验签：本机 Ed25519 不可信")
        }
        return out
    }

    // ── 包裹路径 ──

    private fun wrappingKey(): SecretKey {
        val ks = keyStore()
        (ks.getEntry(WRAP_ALIAS, null) as? KeyStore.SecretKeyEntry)?.let { return it.secretKey }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, PROVIDER)
        generator.init(
            KeyGenParameterSpec
                .Builder(
                    WRAP_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun curveSpec() = EdDSANamedCurveTable.getByName(EdDSANamedCurveTable.ED_25519)

    private fun privateKeyOf(seed: ByteArray): EdDSAPrivateKey =
        EdDSAPrivateKey(EdDSAPrivateKeySpec(seed, curveSpec()))

    private fun wrappedPublicKeyBase64(context: Context): String {
        val pubFile = pubFile(context, IdentityKeyPlan.KEYSTORE_WRAPPED)
        val keyFile = file(context, KEY_FILE)
        if (!keyFile.exists()) {
            if (pubFile.exists()) {
                // 有公钥没私钥 = 对端还认这个身份，本机却签不出来。悄悄新建会变成
                // "两台设备各自以为配对成功"，所以直接失败，让 UI 去问用户。
                throw GeneralSecurityException("包裹私钥文件缺失而公钥仍在：需要用户显式重置身份（T31）")
            }
            val seed = ByteArray(Ed25519Encoding.RAW_KEY_BYTES).also { SecureRandom().nextBytes(it) }
            val publicKey = privateKeyOf(seed).getAbyte()
            seal(context, seed)
            pubFile.writeText(encode(publicKey))
        } else if (!pubFile.exists()) {
            pubFile.writeText(encode(privateKeyOf(open(context)).getAbyte()))
        }
        return pubFile.readText().trim()
    }

    private fun wrappedSign(context: Context, message: ByteArray): ByteArray {
        val engine = EdDSAEngine(MessageDigest.getInstance(curveSpec().hashAlgorithm))
        engine.initSign(privateKeyOf(open(context)))
        engine.update(message)
        return engine.sign()
    }

    private fun seal(context: Context, seed: ByteArray) {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, wrappingKey())
        file(context, KEY_FILE).writeBytes(WrappedIdentityBlob.encode(cipher.iv, cipher.doFinal(seed)))
    }

    private fun open(context: Context): ByteArray {
        val blob = WrappedIdentityBlob.decode(file(context, KEY_FILE).readBytes())
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, wrappingKey(), GCMParameterSpec(GCM_TAG_BITS, blob.iv))
        return cipher.doFinal(blob.ciphertext)
    }

    /** 诊断用（不含任何秘密材料）。UI 靠它决定"要不要问用户重置身份"。 */
    @Synchronized
    fun state(context: Context): Map<String, Any?> {
        val nativePresent = runCatching { keyStore().containsAlias(NATIVE_ALIAS) }.getOrDefault(false)
        val keyPresent = file(context, KEY_FILE).exists()
        val pubPresent = pubFile(context, IdentityKeyPlan.NATIVE).exists() ||
            pubFile(context, IdentityKeyPlan.KEYSTORE_WRAPPED).exists()
        return mapOf(
            "preferredPlan" to preferredPlan().contractValue,
            "sdkInt" to Build.VERSION.SDK_INT,
            "nativeKeyPresent" to nativePresent,
            "wrappedKeyPresent" to keyPresent,
            "publicKeyCached" to pubPresent,
            // 只有"公钥在、两条路的私钥都不在"才算不一致
            "consistent" to (!pubPresent || keyPresent || nativePresent),
        )
    }

    // ── 编解码（minSdk 24 上没有 java.util.Base64） ──

    private fun encode(bytes: ByteArray): String = Base64.encodeToString(bytes, Base64.NO_WRAP)

    private fun rawOf(base64: String): ByteArray = Base64.decode(base64.trim(), Base64.NO_WRAP)
}
