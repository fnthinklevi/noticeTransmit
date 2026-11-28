package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P2-4 的装配面：`NotificationProcessor` 不许再自己判短信/电话包名，
 * 且短信链路内容不足时必须能回落（返回 false），不能静默吞掉。
 *
 * 为什么是源码守卫：`StatusBarNotification` / `Telephony` / `TelecomManager` 都是
 * Android 框架类，JVM 单测拿不到实例。判据表本身由 [NotificationSourceClassifierTest] 真跑。
 */
class NotificationProcessorSourceClassifyTest {
    private val source = stripComments(
        File("src/main/kotlin/com/fnthink/notice/NotificationProcessor.kt").readText(),
    )

    @Test
    fun `短信电话判定只走唯一分类器`() {
        assertTrue(source.contains("NotificationSourceClassifier.classify("))
        assertFalse("旧的 isSmsPackage 又回来了", source.contains("private fun isSmsPackage("))
        assertFalse("旧的 isCallPackage 又回来了", source.contains("private fun isCallPackage("))
        // 只看**路由那一段**：`detectNotificationType` 里的 contains("sms") 只给历史行
        // 打类型标签、不决定去向，不属这条判据。
        val routing = source.substring(
            source.indexOf("if (packageName == context.packageName)"),
            source.indexOf("val isOngoing"),
        )
        assertFalse("路由段又按包名 contains 判短信", routing.contains("contains(\"sms\")"))
        assertFalse("路由段又按包名 contains 判短信", routing.contains("contains(\".mms\")"))
        assertFalse("路由段又按包名 contains 判电话", routing.contains("contains(\"dialer\")"))
        assertFalse("路由段又按包名 contains 判电话", routing.contains("contains(\"incallui\")"))
    }

    @Test
    fun `默认短信应用与默认拨号器都读了系统答案`() {
        assertTrue(source.contains("Telephony.Sms.getDefaultSmsPackage(context)"))
        assertTrue(source.contains("TelecomManager"))
        assertTrue(source.contains("defaultDialerPackage"))
    }

    @Test
    fun `短信链路内容不足会回落到普通路径`() {
        assertTrue(
            "dispatchSmsFromNotification 必须回 Boolean（true=已交给短信链路）",
            source.contains(
                "private fun dispatchSmsFromNotification(sbn: StatusBarNotification): Boolean",
            ),
        )
        assertTrue("没有 return true 的成功分支", source.contains("return true"))
        assertTrue("内容不足时没有 return false", source.contains("if (sender.isEmpty() || body.isEmpty()) return false"))
        assertTrue("回落没有留日志", source.contains("短信通知内容不足，回落到普通通知路径"))
        // 分类结果 SMS 时必须判返回值，不能像旧版那样调完就 return null。
        val block = source.substring(
            source.indexOf("NotificationSourceClassifier.Kind.SMS ->"),
            source.indexOf("NotificationSourceClassifier.Kind.OTHER ->"),
        )
        assertTrue("短信分支没有按返回值决定是否回落", block.contains("if (dispatchSmsFromNotification(sbn)) return null"))
    }
}
