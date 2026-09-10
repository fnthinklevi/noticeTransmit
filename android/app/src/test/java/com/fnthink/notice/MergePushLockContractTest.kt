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
 *
 * ⚠⚠ **本测试属于「源码结构守卫」，改动生产代码结构时必须同步更新本文件** ⚠⚠
 *
 * 三条已知脆弱点（是守卫性测试的固有代价，当前判定"可接受"）：
 * 1. [`synchronizedBodies`]/[`functionBody`] 用**大括号字符配平**提取函数体，不识别
 *    注释与字符串字面量中的 `{`/`}`。若在受保护函数体内写入含大括号的注释或字符串，
 *    提取会提前截断 → 断言可能漏检。**加此类内容后请跑一次本测试确认仍为绿。**
 * 2. [`repoRoot`] 靠 `File("../..")`/`"."`/`".."` 三选一探测，依赖 Gradle 的 cwd；
 *    若构建方式或 AGP 版本改变导致 cwd 变化，会直接 `error()` 报错（**响亮失败，不静默**）。
 * 3. 断言基于源码文本（正则/`contains`），**格式化工具可能让弱断言静默失效**——
 *    因此本类一律避免硬编码换行符与空白，改用结构化正则定位函数体后再断言。
 *    写新断言时请遵循同一原则（历史教训：`contains("X,\n")` 在参数换行后恒真）。
 *
 * ⚠ **断言前必须剥离注释**（本轮踩坑）：修掉 `synchronizedList` 后，代码注释里保留了
 * 「此前用 synchronizedList + 独立 lock」的说明，导致「不得出现 synchronizedList」的
 * 断言**假失败**——解释「为什么改了」反而触发失败。现统一经 [`stripComments`] 处理，
 * 断言只看可执行代码。
 *
 * 心法：本类守卫的是「结构性约束」，行为正确性由 `MergeDeliveryResultTest` 等行为测试覆盖，
 * 两者互补——不要用本类替代行为测试。
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

    /**
     * 提取带 `@Synchronized` 标注的函数体（按大括号配平，粗略但足够），并剥离注释。
     *
     * 剥离注释的原因见 [functionBody]：守卫断言只看代码，注释里的同名字样会误伤。
     */
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
            result.add(name to stripComments(source.substring(bodyStart, i + 1)))
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
        // 送达状态不得写死 SUCCESS：
        // 旧写法 `contains("DeliveryStatus.SUCCESS,\n") && !contains(...)` 硬编码了换行符，
        // 一旦格式化把参数挪行/合并就静默失效（断言恒真）。
        // 改为结构化：定位 flushMergedGroup 函数体，禁止体内出现「构造 ParseResult(SUCCESS」的写法。
        val body = functionBody(service, "flushMergedGroup")
        assertFalse(
            "flushMergedGroup 不得凭空构造 DeliveryStatus.SUCCESS 作为回传结果 —— " +
                "必须来自 sendWebhooksOnly 的真实回调（写死即「假成功」，比报失败更危险）",
            Regex("""ParseResult\(\s*[^)]*DeliveryStatus\.SUCCESS""").containsMatchIn(body)
        )
        assertTrue(
            "flushMergedGroup 必须通过 sendWebhooksOnly 的 onAllComplete 回调获取真实结果",
            body.contains("sendWebhooksOnly(") && body.contains("result")
        )
    }

    // ===== 约束 5：多通道汇总的并发约定（结果集与计数同锁 + 汇总至多一次）=====

    @Test
    fun multiChannelAggregationUsesSingleLockAndFiresOnce() {
        val sender = kotlinSource("WebhookSender.kt")
        // 提取 sendWebhooksOnly 函数体（多通道汇总逻辑所在）
        val body = functionBody(sender, "sendWebhooksOnly")

        assertTrue(
            "多通道汇总必须用 AtomicBoolean（或等价的一次性门闩）保证汇总回调至多触发一次 —— " +
                "若某通道 onResult 被调用两次，计数会提前达标，在结果不全时汇总（可能选出非最差者）",
            body.contains("AtomicBoolean") && body.contains("compareAndSet(")
        )
        assertFalse(
            "结果集不得再用 synchronizedList —— 它与独立的计数锁是两把锁保护同一批状态，" +
                "后人极易在其中一处漏加锁；应统一为「普通 ArrayList + 单锁内 add/读」",
            body.contains("synchronizedList")
        )
        assertTrue(
            "结果收集必须在 synchronized 临界区内完成（与计数共用同一把锁）",
            Regex("""synchronized\(lock\)\s*\{[^}]*results\.add""").containsMatchIn(body)
        )
    }

    /**
     * 提取指定函数的函数体（按大括号配平），并**剥离注释**。
     *
     * 剥离注释是必需的：守卫断言（如「不得出现 synchronizedList」）会被**说明性注释**
     * 里的同名字样误伤——本轮实际踩坑：修掉同步集合后，代码注释里保留了
     * 「此前用 synchronizedList + 独立 lock」的说明，导致断言假失败。
     * 静态源守卫必须只看代码、不看注释，否则「解释为什么改了」反而会触发失败。
     *
     * ⚠ 与 [synchronizedBodies] 同源局限：按字符配平、不识别字符串字面量里的
     * 大括号。**源码结构变更时需同步更新本测试**（已在类注释中标注）。
     */
    private fun functionBody(source: String, funName: String): String {
        val funIdx = source.indexOf("fun $funName(")
        assertTrue("未找到函数 $funName", funIdx >= 0)
        val bodyStart = source.indexOf('{', funIdx)
        assertTrue("函数 $funName 无函数体", bodyStart >= 0)
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
        return stripComments(source.substring(bodyStart, i + 1))
    }

    /**
     * 剥离行注释与块注释（保守实现：不做字符串字面量感知，
     * 因为本仓库受守卫的代码中不存在含双斜杠的字符串字面量；若将来出现需升级本方法）。
     */
    private fun stripComments(code: String): String {
        val noBlock = Regex("""/\*[\s\S]*?\*/""").replace(code, " ")
        return noBlock.lineSequence()
            .joinToString("\n") { line ->
                val idx = line.indexOf("//")
                if (idx >= 0) line.substring(0, idx) else line
            }
    }
}
