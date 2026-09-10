package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 聚合推送架构约束的静态守卫（JVM 直测，无需 Android 运行时）。
 *
 * `MergePushManager` 依赖 `Context`，无法在 JVM 单测里直接实例化；但它有两条
 * **改回去就会出事**的架构约束，必须被自动化守住——否则只靠代码注释，后人重构时
 * 极易踩回同一个坑（本项目的历史缺陷几乎都是这样产生的）。
 *
 * 本类用**源码静态断言**代替行为测试：约束本身是"结构性的"（某处不得出现某调用），
 * 静态检查恰好是这类约束最直接、最不易漏的表达方式。
 */
class MergePushLockContractTest {

    private val repoRoot: File = run {
        // Gradle 测试工作目录随 AGP/启动方式变化，逐个探测而不猜路径
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull { File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory }
            ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun kotlinSource(name: String): String {
        val f = File(
            repoRoot,
            "android/app/src/main/kotlin/com/fnthink/notice/$name"
        )
        assertTrue("源文件不存在: ${f.absolutePath}", f.isFile)
        return f.readText()
    }

    /** 提取带 `@Synchronized` 标注的函数体（按大括号配平，粗略但足够） */
    private fun synchronizedBodies(source: String): List<Pair<String, String>> {
        val result = ArrayList<Pair<String, String>>()
        val marker = "@Synchronized"
        var idx = source.indexOf(marker)
        while (idx >= 0) {
            val funIdx = source.indexOf("fun ", idx)
            if (funIdx < 0) break
            val nameEnd = source.indexOf('(', funIdx)
            val name = source.substring(funIdx + 4, nameEnd).trim()
            val bodyStart = source.indexOf('{', nameEnd)
            if (bodyStart < 0) break
            var depth = 0
            var i = bodyStart
            while (i < source.length) {
                when (source[i]) {
                    '{' -> depth++
                    '}' -> {
                        depth--
                        if (depth == 0) break
                    }
                }
                i++
            }
            result.add(name to source.substring(bodyStart, i + 1))
            idx = source.indexOf(marker, i)
        }
        return result
    }

    // ===== 约束 1：@Synchronized 临界区内不得出现任何网络 IO / 推送调用 =====

    @Test
    fun synchronizedMethodsContainNoNetworkIo() {
        val source = kotlinSource("MergePushManager.kt")
        val bodies = synchronizedBodies(source)
        assertTrue("未解析到任何 @Synchronized 方法（源码结构可能已变，需更新本测试）", bodies.isNotEmpty())

        // 这些调用一旦出现在锁内，就会以对象锁为单位阻塞前台通知刷新，
        // 并可能经 DeliveryNotifier → 广播 → Flutter 回调形成跨线程等待死锁
        val forbidden = listOf(
            "sendWebhooksOnly",
            "sendNotification(",
            "NetworkClient.",
            "WebhookSender(",
            "WebhookSender.",
            "DeliveryNotifier.notify",
            "dispatchEmail",
        )
        for ((name, body) in bodies) {
            for (call in forbidden) {
                assertFalse(
                    "@Synchronized fun $name 的临界区内出现 `$call` —— " +
                        "网络 IO 不得在锁内执行（会阻塞前台通知刷新并可能死锁）。" +
                        "应改为「锁内取快照，锁外推送」。",
                    body.contains(call)
                )
            }
        }
    }

    // ===== 约束 2：本类不得自行构造 WebhookSender =====

    @Test
    fun doesNotConstructItsOwnWebhookSender() {
        val source = kotlinSource("MergePushManager.kt")
        // 自行 new 出的实例 channelConfigs 恒为空（通道配置只注入到 Service 持有的实例），
        // 会导致推送静默不发出——历史上兜底推送正是因此从未真正发送过
        assertFalse(
            "MergePushManager 不得自行构造 WebhookSender：新建实例没有注入通道配置，" +
                "推送会静默不发出。推送应由 NotificationMonitorService.flushMergedGroup 执行。",
            source.contains("WebhookSender(")
        )
    }

    // ===== 约束 3：append 必须把超限组交出去，而不是自己推送 =====

    @Test
    fun appendReturnsOverflowGroupsInsteadOfPushing() {
        val source = kotlinSource("MergePushManager.kt")
        val bodies = synchronizedBodies(source)
        val append = bodies.firstOrNull { it.first == "append" }
            ?: error("未找到 append 方法（签名可能已变，需更新本测试）")

        // append 必须返回超限组，交由调用方在锁外推送
        assertTrue(
            "append 应返回 List<MergeGroup>（超限组交由调用方在锁外推送）",
            source.contains("fun append(") && source.contains("): List<MergeGroup>")
        )
        // 且其临界区内不得做推送
        assertFalse(
            "append 临界区内出现推送调用",
            append.second.contains("sendWebhooksOnly")
        )
    }

    // ===== 约束 4：到点推送与兜底推送必须共用同一实现 =====

    @Test
    fun bothMergePathsShareSingleFlushImplementation() {
        val service = kotlinSource("NotificationMonitorService.kt")
        // 只有一处定义，且两处调用点都指向它
        assertEquals(
            "flushMergedGroup 应只有一处定义",
            1,
            Regex("private fun flushMergedGroup\\(").findAll(service).count()
        )
        val calls = Regex("flushMergedGroup\\(").findAll(service).count() - 1 // 减去定义本身
        assertTrue(
            "flushMergedGroup 调用点应 ≥2（到点推送 + 超限兜底），实际 $calls —— " +
                "两处若各自实现，行为必然分叉（历史上兜底推送就漏了通道配置注入）",
            calls >= 2
        )
        // 送达状态不得写死 SUCCESS
        assertFalse(
            "flushMergedGroup 不得写死 DeliveryStatus.SUCCESS 作为回传结果",
            service.contains("DeliveryStatus.SUCCESS,\n") &&
                !service.contains("result.status == WebhookResponseParser.DeliveryStatus.SUCCESS")
        )
    }
}
