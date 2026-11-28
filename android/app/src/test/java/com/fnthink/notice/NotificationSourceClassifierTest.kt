package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Test

/**
 * P2-4：包名启发式误伤的判据表。
 *
 * 旧实现用 `contains("sms") / contains(".mms") / contains("dialer") / contains("incallui")`：
 * 名字里带这些词的非短信/非拨号应用，整包通知被送进专用链路后直接丢掉。
 * 这里逐档钉住新判据：默认应用精确匹配 > 已知系统组件前缀 > 类别对得上，其余普通通知。
 */
class NotificationSourceClassifierTest {
    private fun classify(
        pkg: String,
        category: String? = null,
        smsDefault: String = "",
        dialerDefault: String = "",
    ) = NotificationSourceClassifier.classify(pkg, category, smsDefault, dialerDefault)

    @Test
    fun `类别常量与 AOSP 同值`() {
        assertEquals(android.app.Notification.CATEGORY_MESSAGE, NotificationSourceClassifier.CATEGORY_MESSAGE)
        assertEquals(android.app.Notification.CATEGORY_CALL, NotificationSourceClassifier.CATEGORY_CALL)
    }

    @Test
    fun `系统默认短信应用精确命中`() {
        assertEquals(
            NotificationSourceClassifier.Kind.SMS,
            classify("com.miui.custom.sms", smsDefault = "com.miui.custom.sms"),
        )
        // 默认应用比较不区分大小写与首尾空白。
        assertEquals(
            NotificationSourceClassifier.Kind.SMS,
            classify("com.miui.custom.sms", smsDefault = " Com.MIUI.Custom.SMS "),
        )
    }

    @Test
    fun `已知系统短信包前缀命中`() {
        assertEquals(NotificationSourceClassifier.Kind.SMS, classify("com.android.mms"))
        assertEquals(NotificationSourceClassifier.Kind.SMS, classify("com.android.mms.ui.Sub"))
    }

    @Test
    fun `名字含 sms 的普通应用不再被吞`() {
        // 审计验收：名字含 sms 的非短信应用通知照常转发。
        assertEquals(NotificationSourceClassifier.Kind.OTHER, classify("com.example.smsbackup"))
        assertEquals(NotificationSourceClassifier.Kind.OTHER, classify("com.acme.smsmarketing"))
        assertEquals(NotificationSourceClassifier.Kind.OTHER, classify("com.foo.mmsreader"))
    }

    @Test
    fun `短信包发的非消息通知走普通路径`() {
        // 短信应用的"备份完成/存储告警"不该被送进短信链路（那里要求发送者+正文，否则丢）。
        assertEquals(
            NotificationSourceClassifier.Kind.OTHER,
            classify("com.android.mms", category = "status"),
        )
        assertEquals(
            NotificationSourceClassifier.Kind.SMS,
            classify("com.android.mms", category = NotificationSourceClassifier.CATEGORY_MESSAGE),
        )
    }

    @Test
    fun `系统默认拨号器命中`() {
        assertEquals(
            NotificationSourceClassifier.Kind.CALL,
            classify("com.acme.phone", dialerDefault = "com.acme.phone"),
        )
    }

    @Test
    fun `名字含 dialer 或 incallui 的普通应用不再被吞`() {
        assertEquals(NotificationSourceClassifier.Kind.OTHER, classify("com.example.dialerwidget"))
        assertEquals(NotificationSourceClassifier.Kind.OTHER, classify("com.example.incalluitips"))
    }

    @Test
    fun `已知来电界面前缀命中`() {
        assertEquals(NotificationSourceClassifier.Kind.CALL, classify("com.samsung.android.incallui"))
        assertEquals(NotificationSourceClassifier.Kind.CALL, classify("com.vivo.incallui.card"))
    }

    @Test
    fun `拨号器发的非通话通知走普通路径`() {
        assertEquals(
            NotificationSourceClassifier.Kind.OTHER,
            classify("com.android.dialer", category = "promo"),
        )
        assertEquals(
            NotificationSourceClassifier.Kind.CALL,
            classify("com.android.dialer", category = NotificationSourceClassifier.CATEGORY_CALL),
        )
    }

    @Test
    fun `电话进程只在通话类别下跳过`() {
        assertEquals(NotificationSourceClassifier.Kind.CALL, classify("com.android.phone"))
        assertEquals(
            NotificationSourceClassifier.Kind.OTHER,
            classify("com.android.phone", category = "status"),
        )
    }

    @Test
    fun `空包名与无默认应用时不猜`() {
        assertEquals(NotificationSourceClassifier.Kind.OTHER, classify(""))
        assertEquals(NotificationSourceClassifier.Kind.OTHER, classify("com.unknown.app"))
    }
}
