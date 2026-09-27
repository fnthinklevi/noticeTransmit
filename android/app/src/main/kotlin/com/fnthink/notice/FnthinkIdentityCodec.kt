package com.fnthink.notice

import java.io.ByteArrayOutputStream

/**
 * 幻念推送身份密钥（T26 第三片）里**不依赖 Context 与 KeyStore** 的那一层。
 *
 * 放在这里的东西都是"两端各写一遍就会出静默事故"的部分：
 *  - 平台门槛（API 30 才有 KeyStore 原生 Ed25519，而 minSdk 是 24）——判错的表现是
 *    老设备上直接抛 NoSuchAlgorithmException，用户看到的是"这 app 一开就崩"；
 *  - DER 头与裸公钥字节的互换——图省事"切最后 32 字节"的话，任何一把形状相近的别的密钥
 *    都会被当成 Ed25519 公钥发出去，而它永远验不过，现场却一切正常；
 *  - 包裹私钥的落盘格式——截断/串版的 blob 必须拒绝，不能"试着解一下看看"。
 *
 * 真正的 KeyStore 接线（生成、解密到内存、签名）在 [FnthinkIdentityStore]（3-B），需要设备。
 */

/** 私钥走哪条路。契约 `identity.identityKey.belowNativeSdk` 写的就是 [KEYSTORE_WRAPPED] 那个字符串。 */
enum class IdentityKeyPlan(val contractValue: String) {
    /** API 30+：KeyStore 原生 Ed25519，私钥本体从不离开 KeyStore。 */
    NATIVE("androidKeyStoreEd25519"),

    /** API 24–29：软件生成的 Ed25519 私钥，用 KeyStore 里一把**不可导出的** AES-GCM 密钥包裹后落盘。 */
    KEYSTORE_WRAPPED("keystoreWrappedSoftwareKey"),
}

object FnthinkIdentityPolicy {

    /** KeyStore 支持 EdDSA 的最低系统版本。**与契约 `identity.identityKey.nativeMinSdkVersion` 必须一致**，
     *  由 `test/architecture/fnthink_identity_contract_test.dart` 跨语言钉住。 */
    const val NATIVE_MIN_SDK_VERSION = 30

    fun planFor(sdkInt: Int): IdentityKeyPlan =
        if (sdkInt >= NATIVE_MIN_SDK_VERSION) IdentityKeyPlan.NATIVE else IdentityKeyPlan.KEYSTORE_WRAPPED

    /**
     * 能力位 `keystoreBacked`：只有原生路径为 true。
     *
     * ⚠ 不要为了好看把包裹路径也叫 keystoreBacked —— 那条路上"不可导出"的是**包裹密钥**，
     * 私钥明文在运行期是进过内存的。对端与用户都有权知道这个差别（它决定被盗后的影响面）。
     */
    fun keystoreBacked(plan: IdentityKeyPlan): Boolean = plan == IdentityKeyPlan.NATIVE

    /** 30 以下的降级路径是否被允许。契约若被改成 `softwarePlaintext`，这里必须拒绝工作。 */
    fun isAcceptableBelowNativeSdk(contractValue: String): Boolean =
        contractValue == IdentityKeyPlan.KEYSTORE_WRAPPED.contractValue
}

/** Ed25519 的 DER 包装与裸 32 字节之间的互换。两端传的是**裸公钥**（T27 服务端按 32 字节收）。 */
object Ed25519Encoding {

    const val RAW_KEY_BYTES = 32

    /** SubjectPublicKeyInfo：`SEQUENCE { SEQUENCE { OID Ed25519 } BIT STRING }` 的固定 12 字节头。 */
    private val SPKI_PREFIX = byteArrayOf(
        0x30, 0x2a, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70, 0x03, 0x21, 0x00,
    )

    /** PKCS#8 v1：`SEQUENCE { INTEGER 0, SEQUENCE { OID Ed25519 }, OCTET STRING(32) }` 的固定 16 字节头。 */
    private val PKCS8_PREFIX = byteArrayOf(
        0x30, 0x2e, 0x02, 0x01, 0x00, 0x30, 0x05, 0x06, 0x03, 0x2b, 0x65, 0x70,
        0x04, 0x22, 0x04, 0x20,
    )

    private fun strip(prefix: ByteArray, encoded: ByteArray, what: String): ByteArray {
        if (encoded.size != prefix.size + RAW_KEY_BYTES) {
            throw IllegalArgumentException(
                "$what 长度 ${encoded.size} 不是 ${prefix.size + RAW_KEY_BYTES} 字节，不是 Ed25519 的包装",
            )
        }
        for (i in prefix.indices) {
            if (encoded[i] != prefix[i]) {
                throw IllegalArgumentException(
                    "$what 的 DER 头与 Ed25519 不符（第 $i 字节应为 ${prefix[i]}，实为 ${encoded[i]}）：" +
                        "宁可不发，也别切一把形状相近的别的密钥当公钥",
                )
            }
        }
        return encoded.copyOfRange(prefix.size, encoded.size)
    }

    private fun wrap(prefix: ByteArray, raw: ByteArray, what: String): ByteArray {
        if (raw.size != RAW_KEY_BYTES) {
            throw IllegalArgumentException("$what 必须是 $RAW_KEY_BYTES 字节，实为 ${raw.size}")
        }
        val out = ByteArrayOutputStream(prefix.size + raw.size)
        out.write(prefix, 0, prefix.size)
        out.write(raw, 0, raw.size)
        return out.toByteArray()
    }

    fun rawPublicFromSpki(encoded: ByteArray): ByteArray = strip(SPKI_PREFIX, encoded, "公钥(SPKI)")

    fun spkiFromRawPublic(raw: ByteArray): ByteArray = wrap(SPKI_PREFIX, raw, "裸公钥")

    fun rawPrivateFromPkcs8(encoded: ByteArray): ByteArray =
        strip(PKCS8_PREFIX, encoded, "私钥(PKCS#8)")

    fun pkcs8FromRawPrivate(raw: ByteArray): ByteArray = wrap(PKCS8_PREFIX, raw, "裸私钥种子")

    // ⚠ base64 的编解码**不在这里**：设备侧要 API 24 可用就只能用 android.util.Base64，
    // 而它在 JVM 单测里是"返回默认值"的桩（`isReturnDefaultValues = true`）—— 放进来只会得到
    // 一条永远测不到的死函数。它属于 KeyStore 接线那一片（3-B），随仪器测试一起做。
}

/** 包裹后的私钥 blob：`MAGIC | version | iv(12) | ciphertext(32+16)`。 */
object WrappedIdentityBlob {

    private val MAGIC = byteArrayOf('F'.code.toByte(), 'T'.code.toByte(), 'W'.code.toByte(), 'K'.code.toByte())
    const val VERSION: Byte = 1
    const val IV_BYTES = 12
    const val GCM_TAG_BYTES = 16

    /** 明文是 Ed25519 的 32 字节种子；AES-GCM 原样把 tag 接在密文后面。 */
    val CIPHERTEXT_BYTES: Int = Ed25519Encoding.RAW_KEY_BYTES + GCM_TAG_BYTES

    data class Sealed(val iv: ByteArray, val ciphertext: ByteArray) {
        override fun toString(): String = "SealedKey(iv=${iv.size}B, ciphertext=${ciphertext.size}B)"
    }

    fun encode(iv: ByteArray, ciphertext: ByteArray): ByteArray {
        require(iv.size == IV_BYTES) { "iv 必须是 $IV_BYTES 字节，实为 ${iv.size}" }
        require(ciphertext.size == CIPHERTEXT_BYTES) {
            "密文必须是 $CIPHERTEXT_BYTES 字节（32 字节种子 + 16 字节 tag），实为 ${ciphertext.size}"
        }
        val out = ByteArrayOutputStream(MAGIC.size + 1 + iv.size + ciphertext.size)
        out.write(MAGIC, 0, MAGIC.size)
        out.write(VERSION.toInt())
        out.write(iv, 0, iv.size)
        out.write(ciphertext, 0, ciphertext.size)
        return out.toByteArray()
    }

    /** 严格解析：截断、串版、别人的 blob 一律抛，**不"试着解一下"**。 */
    fun decode(blob: ByteArray): Sealed {
        if (blob.size < MAGIC.size + 1) throw IllegalArgumentException("blob 太短（${blob.size} 字节），不是包裹私钥")
        for (i in MAGIC.indices) {
            if (blob[i] != MAGIC[i]) throw IllegalArgumentException("blob 头不是 ${String(MAGIC)}，不是本功能的包裹私钥")
        }
        if (blob[MAGIC.size] != VERSION) {
            throw IllegalArgumentException(
                "包裹格式版本 ${blob[MAGIC.size]}，本实现只认 $VERSION：跨版本必须走迁移，不能猜",
            )
        }
        val expected = MAGIC.size + 1 + IV_BYTES + CIPHERTEXT_BYTES
        if (blob.size != expected) {
            throw IllegalArgumentException("blob 长度 ${blob.size}，应为 $expected（可能被截断或尾部被动过）")
        }
        return Sealed(
            blob.copyOfRange(MAGIC.size + 1, MAGIC.size + 1 + IV_BYTES),
            blob.copyOfRange(MAGIC.size + 1 + IV_BYTES, blob.size),
        )
    }
}

/**
 * 身份卡片的**对外形状**。⚠ 这里刻意**没有**任何私钥字段（也不许将来加）：
 * 有这个类型出现在日志/返回值里，就等于保证泄露不了秘密。
 * `FnthinkIdentityContractTest` 用反射钉住这条。
 */
data class FnthinkIdentity(
    val publicKeyBase64: String,
    val plan: IdentityKeyPlan,
) {
    val keystoreBacked: Boolean get() = FnthinkIdentityPolicy.keystoreBacked(plan)

    override fun toString(): String =
        "FnthinkIdentity(publicKey=${publicKeyBase64.take(8)}…, plan=${plan.name}, keystoreBacked=$keystoreBacked)"
}
