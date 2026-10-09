package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 「测试并保存」那一发的生命周期守卫（T112 ① 的原生那一半）。
 *
 * 现象不是慢，是**永远**：整发跑在 `activityScope`（`activityJob + Dispatchers.Main`）里，
 * 而回包只在末尾发一次。`activityJob` 一被取消（离开该页／系统回收／重建），协程连同
 * `MethodChannel.Result` 一起消失 —— Dart 的 `await` 既不完成也不抛，界面就停在「发送中」。
 * 这一族的判据本来就有两条腿，各钉一条，不许合成一条计数（那样任一条失效都能被另一条蒙过去）：
 *
 *  - ① 发送不挂在 UI 生命周期上（挂在 `requestScope`），且**回包仍在主线程**：
 *    把 `withContext(Main)` 一起搬走会让 `MethodChannel` 在非主线程回话，那是把「没人答」
 *    换成「当场崩」；
 *  - ② `requestScope` 不是 `activityJob` 换个名字 —— 否则这条修复只是文字游戏；
 *  - ③ 它也不在 `onDestroy` 里被取消，而 `activityJob` **仍然**要在那里取消：
 *    反向的护栏，防止有人为了过①②把整条 Activity 生命周期拆掉，那会波及仍在
 *    [activityScope] 上的其余 handler。
 *
 * 引擎已 detach 时回包会被 `FlutterJNI` 丢弃并只写一条日志（实测其字节码：`isAttached()` 为假
 * 走 log-and-return，不是抛），那种情况下由 Dart 侧 `kTestWebhookBudget` 的上限复位界面。
 */
class WebhookTestReplyLifecycleGuardTest {

    private val activitySource: String by lazy {
        stripComments(appFile("src/main/kotlin/com/fnthink/notice/MainActivity.kt").readText())
    }

    private val webhookBody: String by lazy {
        bodyOf(activitySource, "internal fun testWebhook(")
    }

    @Test
    fun theTestRequestDoesNotRideTheUiLifecycleScope() {
        assertTrue(
            "提取器没拿到 testWebhook 的正文 —— 这条守卫会在下面几条里空转，先报这里",
            webhookBody.contains("WebhookResponseParser.parse"),
        )
        assertTrue(
            "testWebhook 必须挂在 requestScope 上：挂在 activityScope 上时，activityJob 一取消，" +
                "飞行中的请求连同回包一起没了，Dart 的 await 既不完成也不抛",
            webhookBody.contains("requestScope.launch(Dispatchers.IO)"),
        )
        assertFalse(
            "testWebhook 的正文里不许再出现 activityScope（含「先 requestScope 再绕回 activityScope 回包」）",
            webhookBody.contains("activityScope"),
        )
    }

    @Test
    fun theReplyStillGoesOutOnTheMainThread() {
        assertTrue(
            "回包必须仍在 withContext(Dispatchers.Main) 里发：MethodChannel 的 result 不是线程无关的",
            webhookBody.contains("withContext(Dispatchers.Main)"),
        )
    }

    @Test
    fun theRequestScopeIsNotTheActivityJobRenamed() {
        val declaration = activitySource
            .lines()
            .firstOrNull { it.contains("private val requestScope = CoroutineScope(") }
        assertTrue(
            "requestScope 必须自己有一个不依赖 Activity 的 Job —— 直接抄 activityJob 等于没修",
            declaration != null &&
                declaration.contains("SupervisorJob()") &&
                !declaration.contains("activityJob"),
        )
    }

    @Test
    fun onDestroyStopsCancellingTheUiScopeButNotTheRequestScope() {
        val onDestroy = bodyOf(activitySource, "override fun onDestroy()")
        assertTrue(
            "activityJob 仍然要在 onDestroy 取消：这条守卫只把「正在等回话的请求」摘出去，" +
                "不是在拆 Activity 的生命周期",
            onDestroy.contains("activityJob.cancel()"),
        )
        assertFalse(
            "onDestroy 里不许取消 requestScope —— 那正好把本片要修的失效方式又装回去",
            onDestroy.contains("requestScope"),
        )
    }

    /** gradle 跑测试时的 cwd 可能是模块根，也可能是仓库根的上一层：向上找，别把守卫变成「读不到文件所以通过」。 */
    private fun appFile(rel: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

    /** 取一个函数从签名那一行到与之配对的 `}` 的正文（够钉住调用点，不引解析器）。 */
    private fun bodyOf(source: String, signaturePrefix: String): String {
        val start = source.indexOf(signaturePrefix)
        assertTrue("源码里找不到 $signaturePrefix —— 它被改名或删掉了？", start >= 0)
        val bodyStart = source.indexOf("{", start)
        var depth = 0
        var i = bodyStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> depth--
            }
            if (depth == 0) return source.substring(bodyStart, i + 1)
            i++
        }
        throw AssertionError("$signaturePrefix 的正文花括号不配对")
    }
}
