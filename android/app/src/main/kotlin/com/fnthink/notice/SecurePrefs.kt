package com.fnthink.notice

import android.content.Context
import android.content.SharedPreferences
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Log
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * 原生端加密存储访问器（C2）。
 *
 * 与 flutter_secure_storage 9.2.4（encryptedSharedPreferences: true）保持完全同源：
 * - 同一文件：`FlutterSecureStorage`
 * - 同一主密钥：AndroidKeyStore 中 alias 为 [MasterKey.DEFAULT_MASTER_KEY_ALIAS]
 * - 同一加密方案：PrefKey AES256_SIV + PrefValue AES256_GCM
 *
 * 因此 Flutter 端经 flutter_secure_storage 写入的 `secure_webhook_channels` 等键，
 * 原生端可在此直接读取；原生端写入的键 Flutter 端同样可读。
 *
 * ⚠️ 低版本系统（API < 23）不支持 EncryptedSharedPreferences，
 * 构造失败时回退普通 SharedPreferences（此时无加密保护，保持旧行为）。
 */
object SecurePrefs {
    private const val TAG = "SecurePrefs"
    private const val FILE_NAME = "FlutterSecureStorage"

    private val cache = HashMap<Context, SharedPreferences>()

    /** 与 flutter_secure_storage 的 initializeEncryptedSharedPreferencesManager 参数一致 */
    private fun buildMasterKey(context: Context): MasterKey {
        return MasterKey.Builder(context)
            .setKeyGenParameterSpec(
                KeyGenParameterSpec.Builder(
                    MasterKey.DEFAULT_MASTER_KEY_ALIAS,
                    KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
                )
                    .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                    .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                    .setKeySize(256)
                    .build(),
            )
            .build()
    }

    fun get(context: Context): SharedPreferences {
        cache[context.applicationContext]?.let { return it }
        val prefs = try {
            EncryptedSharedPreferences.create(
                context.applicationContext,
                FILE_NAME,
                buildMasterKey(context.applicationContext),
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM,
            )
        } catch (e: Exception) {
            // API < 23 或 KeyStore 异常时降级为明文，避免功能不可用
            Log.w(TAG, "EncryptedSharedPreferences 不可用，降级明文", e)
            context.applicationContext.getSharedPreferences(FILE_NAME, Context.MODE_PRIVATE)
        }
        cache[context.applicationContext] = prefs
        return prefs
    }
}
