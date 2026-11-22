package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P1-3：邮件授权码写入**不许回退明文**。
 *
 * 旧行为：`EncryptedSharedPreferences` 写失败时把密码 JSON 写回
 * `email_channel_passwords`（普通 SharedPreferences，磁盘上可读），只打一条 Log.e，
 * 界面照样显示「已保存」。用户以为授权码被加密，实际明文躺在应用私有目录里。
 *
 * 现在钉三件互相独立的事（缺任何一条，缺陷都会以另一种形状回来）：
 * 1. 写之前先问 `SecurePrefs.isEncrypted` —— 光靠 try/catch 挡不住
 *    「SecurePrefs 已降级成普通 prefs，putString 根本不抛异常」这条更常见的路；
 * 2. 源码里不再存在明文写入（`putString(KEY_PASSWORDS`），且旧明文键无论成败都清掉；
 * 3. `saveChannels` 返回 Boolean、handler 把 `secure` 回报给 Dart —— 否则 fail-closed
 *    只是把"静默明文"换成"静默丢失"，用户仍然不知道后台发信拿不到授权码。
 */
class EmailPasswordFailClosedContractTest {
    private fun source(name: String): String = stripComments(
        File("src/main/kotlin/com/fnthink/notice/$name").readText(),
    )

    @Test
    fun `加密存储不可用时保存返回 false 且不写明文`() {
        val email = source("EmailManager.kt")
        assertTrue(
            "saveChannels 必须把「密码是否真正加密落盘」回报出去（void 等于让界面继续撒谎）",
            email.contains(
                "fun saveChannels(context: Context, channelsData: List<Map<String, Any?>>): Boolean",
            ),
        )
        assertTrue(
            "写密码前必须先问加密存储是否真的可用（SecurePrefs 会静默降级成普通 prefs）",
            email.contains("SecurePrefs.isEncrypted(context)"),
        )
        assertFalse(
            "又出现明文写入：加密失败时 putString(KEY_PASSWORDS…) 就是 P1-3",
            email.contains("putString(KEY_PASSWORDS"),
        )
        assertTrue(
            "旧明文键无论成败都要清掉，否则读取侧会静默沿用旧密码",
            email.contains("remove(KEY_PASSWORDS)"),
        )
        // 失败分支只允许 return false，绝不能悄悄写别处后返回 true
        val writeBlock = email.substring(
            email.indexOf("private fun writeEncryptedPasswords"),
            email.indexOf("\n    }", email.indexOf("private fun writeEncryptedPasswords")),
        )
        assertTrue("拒绝路径没有 return false", writeBlock.contains("return false"))
        assertFalse(
            "拒绝路径出现了 apply() 以外的落盘动作（疑似回退明文）",
            writeBlock.contains("putString(KEY_PASSWORDS"),
        )
    }

    @Test
    fun `handler 把 secure 结果回报给 Dart`() {
        val handler = source("channels/ConfigChannelHandler.kt")
        assertTrue(
            "setEmailChannels 丢掉了 saveChannels 的返回值",
            handler.contains("val secure = EmailManager.saveChannels(activity, channels)"),
        )
        assertTrue(
            "没把 secure 回报给 Dart：界面拿不到 fail-closed 的信号",
            handler.contains("mapOf(\"secure\" to secure)"),
        )
    }
}
