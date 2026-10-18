package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 「队列里的条目不许静默消失」的架构守卫（T150 片2，维护者 2026-10-12 第 6 条）。
 *
 * 病灶不在界面：延迟队列与聚合队列都有"超出上限就少留几条"的自我保护，而被少留的那条
 * **早已写进推送历史**，送达列停在初值 `pending`。没有下一发回执来推离它，`deliveryPending`
 * 就被读成「发送中」—— 本机再也不会发它，界面却一直说它正在发。片1 把界面那一半修好了
 * （认不出的不再说「发送中」，见 `lib/services/delivery_display.dart`），这一类钉的是原生那一半：
 *
 * ① 重排闹钟时不许把"过期"的条目筛掉（那不是过期日志，是没发的通知）；
 * ② 上限挤出的必须交回调用方，并被真的推出去；
 * ③ 聚合成员被摘出时必须交回，并被回传一个送达说法；
 * ④ 那句说法两种语言都得有；
 * ⑤ 幻念待发队列丢最旧必须逐条回传送达说法（T147③）；
 * ⑥ 扇出路径的上限只有那四把具名尺，且调用点不许写数字（T147①）。
 *
 * ⚠ 与 `MergePushLockContractTest` / `MergeFailureContractTest` 同族：**静态源码断言**，
 * 改生产代码结构时必须同步更新本文件。断言一律打在**结构化位置**（函数体）上，
 * 并先 `stripComments` —— 否则"解释为什么不再这么做"的那句注释会把自己的守卫打红（本仓踩过）。
 * ⚠ 一条用例只钉一件事：每发植入各点名一条，混在一条里的断言等于没有证据。
 */
class QueueNoSilentDropContractTest {

    private val root: String = run {
        val candidates = listOf("../..", "..", ".")
        candidates.firstOrNull { rel ->
            File("$rel/android/app/src/main/kotlin/com/fnthink/notice/DelayedPushManager.kt").exists()
        } ?: throw IllegalStateException("未找到仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun src(rel: String): String =
        stripComments(File("$root/$rel").readText())

    private val delayed = src("android/app/src/main/kotlin/com/fnthink/notice/DelayedPushManager.kt")
    private val merge = src("android/app/src/main/kotlin/com/fnthink/notice/MergePushManager.kt")
    private val service = src("android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt")
    private val fanout = src("android/app/src/main/kotlin/com/fnthink/notice/FnthinkFanoutQueue.kt")

    /** 取函数体（大括号字符配平，不识别字符串里的大括号 —— 与同类守卫同样局限）。 */
    private fun functionBody(source: String, signature: String): String {
        val at = source.indexOf(signature)
        assertTrue("未找到 $signature（源码结构可能已变，需同步更新本测试）", at >= 0)
        val start = source.indexOf('{', at)
        assertTrue("$signature 没有函数体", start >= 0)
        var depth = 0
        var i = start
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
        return source.substring(start, i + 1)
    }

    // ── ① 重排不许丢弃未推送的条目 ────────────────────────────────────────

    @Test
    fun rescheduleAll_rearmsAlarm_withoutRewritingQueue() {
        val body = functionBody(delayed, "fun rescheduleAll()")
        assertFalse(
            "rescheduleAll 不得筛掉条目 —— 延迟队列里是「还没推送的通知」，" +
                "闹钟没赶上就丢，那一行会永远停在「发送中」",
            body.contains("filter {") || body.contains("removeAll")
        )
        assertFalse(
            "rescheduleAll 不许重写队列内容（只重排闹钟）",
            body.contains("writeQueue(")
        )
        assertTrue("必须有重排闹钟调用", body.contains("scheduleNext()"))
    }

    @Test
    fun serviceReschedulesDelayedQueueOnStartup() {
        assertTrue(
            "Service 启动时必须调用 rescheduleAll（进程被杀后靠它把队列续上）",
            service.contains("delayedPushManager.rescheduleAll()")
        )
    }

    // ── ② 上限挤出的必须交回并被真的推出去 ────────────────────────────────

    @Test
    fun enqueueReturnsTheSpilledEntries() {
        assertTrue(
            "enqueue 必须返回被挤出的条目（List<NotificationInfo>），不再一丢了之",
            delayed.contains("fun enqueue(info: NotificationInfo, fireAt: Long): List<NotificationInfo>")
        )
        val body = functionBody(delayed, "fun enqueue(")
        assertTrue("挤出那一步必须走那份纯算术", body.contains("DelayedPushLogic.splitByCap"))
        assertTrue("交回前必须把队列项还原成通知", body.contains("readInfos(spilled)"))
    }

    @Test
    fun queueCapHasASingleAuthor() {
        assertEquals(
            "MAX_QUEUE_SIZE 只许出现在「声明 + 交给纯函数」两处 —— " +
                "第二处自己排序就是长出第二把上限（挤出的到底是什么都说不清）",
            2,
            Regex("MAX_QUEUE_SIZE").findAll(delayed).count(),
        )
    }

    @Test
    fun servicePushesEverySpilledDelayedEntry() {
        assertTrue(
            "Service 必须逐条消费 enqueue 的返回值 —— 整条语句钉死，" +
                "写成 `.take(0)`／`.firstOrNull()` 那种「看起来消费了」的形态要能认出来",
            service.contains(
                "for (spilled in delayedPushManager.enqueue(info, decision.fireAt)) {"
            )
        )
        assertTrue(
            "挤出的那条要走与到点同一条推送路径（回执才会把它推离 pending）",
            Regex("""dispatchToChannels\(\w+, alsoBroadcastRecord = false\)""").containsMatchIn(service)
        )
    }

    // ── ③ 被摘出聚合的成员必须有归宿 ──────────────────────────────────────

    @Test
    fun appendReturnsDroppedMembersToCaller() {
        assertTrue(
            "append 必须返回 AppendResult（toFlush + droppedMembers）",
            merge.contains("): AppendResult")
        )
        val body = functionBody(merge, "fun append(")
        assertTrue("摘成员那一步必须走那份纯算术", body.contains("MergePushLogic.appendMember("))
        assertTrue(
            "两堆都得交回去（T147② 起多交一个组 id）",
            body.contains("AppendResult(toFlush, dropped, memberGroupId)"),
        )
        assertTrue(
            "解析不出载荷时要喊出来，不许静默少一条（拿不到 record id 就给不了送达说法）",
            body.contains("解析失败")
        )
    }

    @Test
    fun serviceReportsDroppedMergeMembersThroughMergePseudoChannel() {
        val loop = Regex("""for \(\w+ in appendResult\.droppedMembers\) \{""").find(service)
        assertTrue("Service 必须逐条处理被摘出的成员", loop != null)
        val segment = service.substring(loop!!.range.first, loop.range.first + 700)
        assertTrue(
            "回传必须走 MERGE 伪通道（扇到该行已有的全部通道键，见 Dart 侧 applyDelivery）",
            segment.contains("DeliveryNotifier.notify(") && segment.contains("\"MERGE\"")
        )
    }

    @Test
    fun droppedMergeMemberIsReportedAsFailedNotIntercepted() {
        val loop = Regex("""for \(\w+ in appendResult\.droppedMembers\) \{""").find(service)
        val segment = service.substring(loop!!.range.first, loop.range.first + 700)
        assertTrue(
            "报 BIZ_FAIL（failed）而不是 PAUSED／intercepted：这不是「规则决定不发」也不是" +
                "「用户按了暂停」，说成后两者会把这一条划出可重推的范围，替用户把门关死",
            segment.contains("DeliveryStatus.BIZ_FAIL")
        )
        assertTrue(
            "理由必须来自那张具名文案，不在页面／服务里现拼一句",
            segment.contains("mergeMemberDroppedReason()")
        )
    }

    // ── ④ 那句理由两种语言都得有 ──────────────────────────────────────────

    @Test
    fun mergeMemberDroppedReason_hasBothLocales() {
        val zh = I18n.mergeMemberDroppedReason()
        I18n.setLocale("en")
        val en: String
        try {
            en = I18n.mergeMemberDroppedReason()
        } finally {
            I18n.setLocale("zh")
        }
        assertEquals("locale 要还原（全局那一份别的用例也在用）", "zh", I18n.getLocale())
        assertTrue("中文那句不许是空", zh.isNotBlank())
        assertTrue("英文那句不许是空 —— 只写中文，英文用户读到的是空格", en.isNotBlank())
        assertNotEquals(
            "两句必须真的不同（`if (isEn)` 那一支抄成中文是这里最省事的坏法）",
            zh,
            en,
        )
    }

    // ── ⑤ 幻念待发队列丢最旧必须留下送达说法（T147③）──────────────────────

    @Test
    fun fanoutEnqueueReturnsDroppedItems() {
        assertTrue(
            "enqueue 必须回 EnqueueResult，不再只回一个计数",
            fanout.contains("fun enqueue(") && fanout.contains("): EnqueueResult"),
        )
        val body = functionBody(fanout, "fun enqueue(")
        assertTrue(
            "挤位那一步必须走那份纯算术",
            body.contains("mergeIntoArray(arr, item, MAX_PENDING)"),
        )
        assertTrue(
            "交回的必须是可回传 id 的条目，不是计数",
            body.contains("EnqueueResult(dropped)") && body.contains("DroppedItem(id"),
        )
    }

    @Test
    fun serviceConsumesEveryDroppedFanoutItem() {
        val body = functionBody(service, "private fun dispatchFnthink(")
        assertTrue(
            "Service 必须逐条消费 enqueue 的 dropped —— 整条循环钉死，" +
                "写成 `.take(0)`／`.firstOrNull()` 那种「看起来消费了」的形态要能认出来",
            body.contains("for (dropped in result.dropped) {"),
        )
    }

    @Test
    fun droppedFanoutItemIsReportedThroughFnthinkChannel() {
        val body = functionBody(service, "private fun dispatchFnthink(")
        val segment = body.substringAfter("for (dropped in result.dropped)").take(700)
        assertTrue(
            "回传必须走幻念那一族的送达键（与推送暂停分支同一个键）",
            segment.contains("DeliveryNotifier.notify(") && segment.contains("\"fnthink\""),
        )
    }

    @Test
    fun droppedFanoutItemIsReportedAsFailedWithNamedReason() {
        val body = functionBody(service, "private fun dispatchFnthink(")
        val segment = body.substringAfter("for (dropped in result.dropped)").take(700)
        assertTrue(
            "报 BIZ_FAIL（failed）而不是 PAUSED／intercepted：这不是「规则决定不发」，" +
                "用户仍该能手动补这一条",
            segment.contains("WebhookResponseParser.DeliveryStatus.BIZ_FAIL"),
        )
        assertTrue(
            "理由必须来自那张具名文案，不在服务里现拼一句",
            segment.contains("I18n.fnthinkFanoutQueueDroppedReason(result.dropped.size)"),
        )
    }

    @Test
    fun fanoutQueueDroppedReason_hasBothLocales() {
        val zh = I18n.fnthinkFanoutQueueDroppedReason(3)
        I18n.setLocale("en")
        val en: String
        try {
            en = I18n.fnthinkFanoutQueueDroppedReason(3)
        } finally {
            I18n.setLocale("zh")
        }
        assertEquals("locale 要还原（全局那一份别的用例也在用）", "zh", I18n.getLocale())
        assertTrue("中文那句不许是空", zh.isNotBlank())
        assertTrue("英文那句不许是空 —— 只写中文，英文用户读到的是空格", en.isNotBlank())
        assertNotEquals(
            "两句必须真的不同（`if (isEn)` 那一支抄成中文是这里最省事的坏法）",
            zh,
            en,
        )
    }

    // ── ⑥ 扇出路径的上限只有一份作者（T147①）────────────────────────────

    @Test
    fun fanoutCapConstantsHaveASingleAuthor() {
        assertEquals(
            "MAX_ITEMS_PER_GROUP 只许出现在「声明 + 交给纯函数」两处",
            2,
            Regex("MAX_ITEMS_PER_GROUP").findAll(merge).count(),
        )
        assertEquals(
            "MAX_PENDING 只许出现在「声明 + 交给纯函数」两处 —— 日志里再引用一次就是第二把尺",
            2,
            Regex("MAX_PENDING").findAll(fanout).count(),
        )
    }

    @Test
    fun fanoutPathsDeclareNoNewCap() {
        val declared = Regex("""const\s+val\s+(MAX_[A-Z0-9_]+)""")
            .findAll(listOf(delayed, merge, fanout, service).joinToString("\n"))
            .map { it.groupValues[1] }
            .toSet()
        assertEquals(
            "扇出路径上的上限常量集合变了 ⇒ 有人新开了一把上限；四把现存的尺是 " +
                "Delayed 队列 / Merge 组数 / Merge 成员数 / 幻念待发队列",
            setOf("MAX_QUEUE_SIZE", "MAX_GROUPS", "MAX_ITEMS_PER_GROUP", "MAX_PENDING"),
            declared,
        )
    }

    @Test
    fun fanoutCapCallSitesUseTheNamedConstant() {
        assertTrue(
            "延迟队列那一发必须把具名上限交给纯函数",
            delayed.contains("splitByCap(filtered, MAX_QUEUE_SIZE)"),
        )
        assertFalse(
            "延迟队列上限不许在调用点写数字",
            Regex("""splitByCap\([^)]*,\s*\d+\s*\)""").containsMatchIn(delayed),
        )
        assertTrue(
            "幻念待发队列那一发必须把具名上限交给纯函数",
            fanout.contains("mergeIntoArray(arr, item, MAX_PENDING)"),
        )
        assertFalse(
            "幻念待发队列上限不许在调用点写数字",
            Regex("""mergeIntoArray\([^)]*,\s*\d+\s*\)""").containsMatchIn(fanout),
        )
        val appendAt = merge.indexOf("MergePushLogic.appendMember(")
        val constantAt = merge.indexOf("MAX_ITEMS_PER_GROUP", appendAt)
        assertTrue(
            "聚合成员那一发必须把具名上限交给纯函数",
            appendAt >= 0 && constantAt > appendAt,
        )
        assertFalse(
            "聚合成员上限不许在调用点写数字",
            Regex("""\b\d+\b""").containsMatchIn(merge.substring(appendAt, constantAt)),
        )
    }
}
