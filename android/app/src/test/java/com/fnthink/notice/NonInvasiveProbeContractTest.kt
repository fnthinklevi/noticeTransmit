package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 6e「非侵入」这条边界本身的守卫（roadmap T09 / 第 6 步 6e）。
 *
 * 两个新方法的**全部价值**在于它们不产生用户可见的副作用：
 * `probeAppChannelToken` 只换 token、`verifySmtp` 只做 SMTP 握手与认证。
 * 一旦有人"顺手"在里面加一条测试消息 / 一封测试邮件，通道状态页每 6 小时自动刷新一次
 * = 每 6 小时给全公司群发一条噪声消息，而且**没有任何测试会红**（真实投递只在真机上看得见）。
 * 所以这条边界必须钉在源码形状上，而不是写在注释里。
 *
 * 顺带钉三件同族事实：探测**不许查 token 缓存**（缓存命中只证明"曾经配对过"，
 * 证明不了这组凭据现在还有效）、两条探测与各自实发路径共用同一份载荷构造、
 * 结论一律回主线程回复（`MethodChannel.Result` 非线程安全，从 IO 线程回复会静默丢失）。
 */
class NonInvasiveProbeContractTest {

    private val mainActivity: String by lazy {
        stripComments(read("src/main/kotlin/com/fnthink/notice/MainActivity.kt"))
    }
    private val emailSender: String by lazy {
        stripComments(read("src/main/kotlin/com/fnthink/notice/EmailSender.kt"))
    }
    private val configHandler: String by lazy {
        stripComments(read("src/main/kotlin/com/fnthink/notice/channels/ConfigChannelHandler.kt"))
    }

    private fun read(path: String): String = File(path).readText()

    /** 从 [signature] 起按花括号配对取整块（含函数体）。找不到就抛 ⇒ 用例红，不是文件加载失败。 */
    private fun blockAfter(source: String, signature: String): String {
        val start = source.indexOf(signature)
        assertTrue("未找到函数：$signature（改名/挪动 ⇒ 本守卫要同步）", start >= 0)
        val bodyStart = source.indexOf('{', start)
        assertTrue("$signature 后没有代码块", bodyStart >= 0)
        var depth = 0
        var i = bodyStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(start, i + 1)
                }
            }
            i++
        }
        return source.substring(start)
    }

    // ———— 应用通道：只换 token ————

    @Test
    fun `token 探测不得触达消息端点`() {
        val block = blockAfter(mainActivity, "internal fun probeAppChannelToken(")
        for (forbidden in listOf("sendTarget(", "buildPayload(", "toRequestBody(")) {
            assertFalse(
                "probeAppChannelToken 里出现 $forbidden ⇒ 它已经会真发消息了：" +
                    "通道状态每 6 小时自动刷新 = 全公司每 6 小时收一条测试噪声",
                block.contains(forbidden)
            )
        }
        assertTrue(
            "必须真的换一次 token（只读缓存不算探测）",
            block.contains(".fetchToken(")
        )
        assertFalse(
            "不得经 AppChannelTokenManager.getToken（会命中缓存：缓存里的 token " +
                "只证明曾经配对过，证明不了这组凭据现在还有效）",
            block.contains("AppChannelTokenManager.getToken")
        )
    }

    @Test
    fun `token 探测与测试发送共用同一份载荷还原`() {
        // 两条路口径一旦分叉，"探测说通、实发失败"就无从解释，状态列也开始说谎。
        val probe = blockAfter(mainActivity, "internal fun probeAppChannelToken(")
        val test = blockAfter(mainActivity, "internal fun testAppChannel(")
        assertTrue("探测不再复用还原函数", probe.contains("appChannelTarget("))
        assertTrue("测试发送不再复用还原函数", test.contains("appChannelTarget("))
        assertEquals(
            "appChannelTarget 只允许定义一处",
            1,
            Regex("private fun appChannelTarget\\(").findAll(mainActivity).count()
        )
    }

    // ———— 邮件：只握手认证 ————

    @Test
    fun `SMTP 探测不得构造或投递邮件`() {
        val block = blockAfter(emailSender, "fun verifyConnection(")
        for (forbidden in listOf("MimeMessage", "Transport.send", "sendMessage", "setFrom(")) {
            assertFalse(
                "verifyConnection 里出现 $forbidden ⇒ 探测会变成真发信，" +
                    "自动刷新会把测试邮件寄给收件人",
                block.contains(forbidden)
            )
        }
        assertTrue("必须真的完成认证握手，否则探测没有结论", block.contains(".connect("))
        assertTrue(
            "会话必须与实发共用 sessionFor（否则探测通≠实发通）",
            block.contains("sessionFor(")
        )
        assertTrue(
            "探测失败必须经 classifyError 分类（徽标之外还要能说出为什么）",
            block.contains("classifyError(")
        )
    }

    // ———— 两条路都必须回主线程回复 ————

    @Test
    fun `结论一律回主线程回复，且只有一个出口`() {
        for ((name, block) in listOf(
            "probeAppChannelToken" to blockAfter(
                mainActivity,
                "internal fun probeAppChannelToken("
            ),
            "verifySmtp" to blockAfter(mainActivity, "internal fun verifySmtp("),
            "testAppChannel" to blockAfter(mainActivity, "internal fun testAppChannel(")
        )) {
            assertTrue(
                "$name 的 result.success 必须包在 withContext(Dispatchers.Main) 里：" +
                    "MethodChannel.Result 非线程安全，从 IO 线程回复是静默丢失",
                Regex("withContext\\(Dispatchers\\.Main\\)[\\s\\S]{0,300}?result\\.success")
                    .containsMatchIn(block)
            )
            assertEquals(
                "$name 应当只有一个回复出口（多处 = 有一条路径漏切回主线程）",
                1,
                Regex("result\\.success").findAll(block).count()
            )
        }
    }

    @Test
    fun `两个新方法都在配置域 handler 里有分支`() {
        // Dart 侧的 parity 守卫锁"Dart 调用 ⇒ 原生必须有分支"；这条锁反方向的形状：
        // 分支必须落在 ConfigChannelHandler（与 probeChannelHealth 同域），不许新开一份抄本。
        for (m in listOf("probeAppChannelToken", "verifySmtp")) {
            assertEquals(
                "$m 的 when 分支只能有一处",
                1,
                Regex("\"$m\"\\s*->").findAll(configHandler).count()
            )
            assertTrue(
                "handler 必须转调 activity.$m",
                configHandler.contains("activity.$m(")
            )
        }
    }

    @Test
    fun `邮件探测的回包必须明说是不是认证失败（T115 护栏②的跨语言判据）`() {
        // 为什么钉这一格：认证失败会让 QQ／163 临时封禁账号，Dart 侧要在自动重探那一路里
        // 挡一道冷却。而 Dart 只看得到 `classifyError` 出来的那句中文 —— 让它去匹配措辞
        // 就成了第二份口径：文案一改冷却静默失效，失效方向恰好是"又开始频繁认证"。
        // 所以判据必须住在原生这一侧，并由回包里那个**布尔**交出去。
        val smtp = blockAfter(mainActivity, "internal fun verifySmtp(")
        assertTrue(
            "verifySmtp 的回包没有 authFailure ⇒ Dart 那一侧的冷却永远不触发",
            smtp.contains("\"authFailure\" to")
        )
        val probe = blockAfter(emailSender, "fun verifyConnection(")
        assertTrue(
            "verifyConnection 不再经 isAuthFailure 分类 ⇒ 那个布尔是硬编的，会随分类漂移",
            probe.contains("isAuthFailure(")
        )
        assertEquals(
            "isAuthFailure 只允许定义一处（两处就会各判各的）",
            1,
            Regex("fun isAuthFailure\\(").findAll(emailSender).count()
        )
    }

    @Test
    fun `冷却只挡自动那一路，下拉那一发必须照样能测`() {
        // 与 Dart 侧 `channel_health_reprobe_guard_test` 同一件事的两面：这里钉的是"探测这一发
        // 仍然是显式意图优先"，那条钉的是"节奏那两发仍然 stale-only"。
        val smtp = blockAfter(mainActivity, "internal fun verifySmtp(")
        assertFalse(
            "verifySmtp 自己不许做冷却/退避：冷却归调用方（Dart 的调度单点），" +
                "否则两处各挡一次，用户点下拉会连发都不发",
            Regex("cooldown|Cooldown|Thread\\.sleep").containsMatchIn(smtp)
        )
    }
}
