package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 原生消息目录（`I18n.msg` / `msgf`）的双语守卫。
 *
 * 背景（2026-11-22 P0-2）：面向用户的错误原因、邮件正文、内置应用名等原先散落在
 * 各处的硬编码中文，已迁入 `I18n.kt` 的 `MESSAGES_ZH` / `MESSAGES_EN`。
 * 这里钉两件事：
 *  1. 英文目录里**一个 CJK 都不能有**（否则英文用户仍会看到中文）；
 *  2. 中文目录保留原措辞，且 `{0}`/`{1}` 占位符真的被替换。
 */
class I18nMessageCatalogTest {
    private val cjk = Regex("[\\u4e00-\\u9fff]")

    private val userFacingKeys = listOf(
        "email.sent", "email.authFailed", "email.bodyDefault", "email.subTextLine",
        "app.wechat", "app.sms", "app.settings",
        "err.bizFailCode", "err.rateLimitErrcode", "err.queuedRetry", "err.noWebhook",
        "notif.channelName", "notif.noTitle", "merge.listSep",
        "test.appChannelMessage", "export.success", "download.notFound",
        "fn.err.signFailed", "identity.noPrivateKey",
    )

    @Test
    fun `english catalog has no CJK for user-facing keys`() {
        try {
            I18n.setLocale("en")
            for (key in userFacingKeys) {
                val text = I18n.msgf(key, "x", "y", "z")
                assertFalse("英文目录里 $key 仍含中文：$text", cjk.containsMatchIn(text))
            }
        } finally {
            I18n.setLocale("zh")
        }
    }

    @Test
    fun `chinese catalog keeps the wording and placeholders substitute`() {
        I18n.setLocale("zh")
        assertTrue(I18n.msg("email.authFailed").contains("认证失败"))
        assertTrue(
            "占位符没有被替换：${I18n.msgf("err.bizFailCode", 400, "bad")}",
            I18n.msgf("err.bizFailCode", 400, "bad").contains("code=400: bad"),
        )
        assertTrue(I18n.msgf("email.subTextLine", "二楼").contains("二楼"))
    }
}
