package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 聚合推送失败语义与兜底能力契约测试（静态源码断言 + 行为断言）。
 *
 * 背景：聚合推送（merge）把窗口期内多条通知合并为**一条** HTTP 请求。这条链路上
 * 「失败后怎么办」有一个必须说清的事实——**聚合组推完即出队，没有二次重试**。
 * 因此内容保底完全依赖「失败被如实回传 + 成员内容已各自落库 + 用户可手动补推」
 * 这三件事同时成立。任一件被改坏，用户就会看到「已合并推送」而内容实际丢失。
 *
 * 本测试把这条契约锁成断言，避免后续重构（尤其是"顺手加个重试"或
 * "失败也标成功省事"）打破它。
 *
 * ⚠ 本文件是**静态源码断言**（读 .kt/.dart 源文本），不启动 Android 运行时。
 *   仓库根目录通过 `../..` / `..` / `.` 逐个探测，不猜路径。
 */
class MergeFailureContractTest {

    private val root: String = run {
        val candidates = listOf("../..", "..", ".")
        candidates.firstOrNull { rel ->
            File("$rel/android/app/src/main/kotlin/com/fnthink/notice/MergePushManager.kt").exists()
        } ?: throw IllegalStateException("未找到仓库根目录")
    }

    private fun src(rel: String): String = File("$root/$rel").readText()

    private val mergeManager = src("android/app/src/main/kotlin/com/fnthink/notice/MergePushManager.kt")
    private val service = src("android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt")
    private val network = src("android/app/src/main/kotlin/com/fnthink/notice/NetworkClient.kt")
    private val webhook = src("android/app/src/main/kotlin/com/fnthink/notice/WebhookSender.kt")
    private val notifService = src("lib/services/notification_service.dart")

    // ── 1. 失败必须如实回传（不得把失败写成成功） ───────────────────────────

    @Test
    fun markMembersDelivered_mapsRealStatusNotHardcodedSuccess() {
        val body = functionBody(mergeManager, "fun markMembersDelivered(")
        assertTrue(
            "markMembersDelivered 必须依据 result.status 判定成功，不能写死 SUCCESS",
            body.contains("result.status ==")
        )
        assertTrue(
            "成功时才应替换为「已合并推送」文案（失败要保留真实原因）",
            body.contains("if (success)") && body.contains("mergeDeliveredLabel()")
        )
        // 失败分支不能把 message 抹掉（用户要知道为什么失败）
        assertFalse(
            "markMembersDelivered 不得无条件用固定文案覆盖失败原因",
            Regex("""for \(member in group\.items\) \{\s*DeliveryNotifier\.notify\(\s*context,\s*member\.id,\s*"MERGE",\s*result\.copy\(""").containsMatchIn(mergeManager)
        )
    }

    @Test
    fun dartMergeBranch_mapsNormalizedNotHardcodedSuccess() {
        val idx = notifService.indexOf("kotlinType == 'MERGE'")
        assertTrue("Dart 侧应有 MERGE 分支", idx >= 0)
        val body = notifService.substring(idx, minOf(idx + 1400, notifService.length))
        assertTrue(
            "Dart MERGE 分支必须用 normalized（真实结果映射），不能写死 'success'",
            body.contains("normalized")
        )
        assertFalse(
            "Dart MERGE 分支出现写死 success 即为回归（历史缺陷）",
            body.contains("'status': 'success'")
        )
    }

    @Test
    fun multiChannelAggregationIsWorstOf_notAnySuccess() {
        // 多通道汇总必须「最差优先」：任一失败即整体失败，不能让成功通道掩盖失败
        val body = functionBody(webhook, "fun sendWebhooksOnly(")
        // ⚠ 必须做**结构化**断言，不能只查 token 是否出现。
        //   首版实现写成 body.contains("maxByOrNull") && body.contains("severity(")，
        //   被植入「先挑成功通道，失败时再退回 maxByOrNull」（any-success）时**未能捕获**——
        //   因为两个 token 在植入后的行里依然存在。改为断言真正的取值表达式。
        assertTrue(
            "多通道汇总必须直接对 results 按 severity 取最大（最差优先）",
            Regex("""results\.maxByOrNull\s*\{\s*severity\(it\.status\)\s*\}""").containsMatchIn(body)
        )
        // 任何"优先挑成功/按成功短路"的写法都是回归：成功通道会掩盖失败
        assertFalse(
            "不得先挑成功通道（any-success 会让失败被成功通道掩盖）",
            Regex("""(firstOrNull|any|first)\s*\{\s*severity\(it\.status\)\s*==\s*0""").containsMatchIn(body)
        )
        assertFalse(
            "不得按 SUCCESS 直接短路判定整体成功",
            Regex("""(any|firstOrNull)\s*\{\s*it\.status\s*==\s*[\w.]*SUCCESS""").containsMatchIn(body)
        )
        assertTrue("无通道必须返回失败态而非成功", webhook.contains("fun noChannelResult()"))
        assertTrue(
            "noChannelResult 必须是 BIZ_FAIL（不能是 SUCCESS）",
            Regex("""fun noChannelResult\(\)[\s\S]{0,220}?DeliveryStatus\.BIZ_FAIL""").containsMatchIn(webhook)
        )
    }

    // ── 2. 聚合组「推完即出队」，因此必须有其他兜底 ─────────────────────────

    @Test
    fun drainDue_removesGroupsBeforePush_soRetryMustBeElsewhere() {
        // drainDue 先写回队列（移除到期组）再返回，调用方推送。
        // 这意味着推送失败后该组**已不在队列**，不会有二次推送。
        val body = functionBody(mergeManager, "fun drainDue()")
        assertTrue(
            "drainDue 必须先 writeQueue 再返回（到期组出队）——这是「无自动重试」的根因",
            body.indexOf("writeQueue(") < body.indexOf("return due")
        )
        // 因此调用方在推送失败时不做任何重新入队：这条也一并锁住，防止误以为有重试
        val flush = functionBody(service, "private fun flushMergedGroup(")
        assertFalse(
            "flushMergedGroup 不得在失败时把组重新入队（当前设计是「不重试」，" +
                "若改为重试必须同步更新本断言与文档，并考虑重复推送风险）",
            flush.contains("append(") || flush.contains("enqueue(")
        )
    }

    @Test
    fun mergeGroupIsNotDroppedOnFailure_onlyMarkedFailed() {
        // 失败时只标注状态、不丢内容：组已被 drain 出队，但成员内容已落库
        val flush = functionBody(service, "private fun flushMergedGroup(")
        assertTrue(
            "无论成功失败都必须回传结果给成员（markMembersDelivered 在回调里无条件调用）",
            flush.contains("markMembersDelivered(group, result)")
        )
        // markMembersDelivered 不能因失败而 return（必须逐成员回传）
        val mark = functionBody(mergeManager, "fun markMembersDelivered(")
        assertFalse(
            "markMembersDelivered 不得在失败时提前 return（否则成员永远停留 pending）",
            Regex("""if \(!success\)\s*return""").containsMatchIn(mark)
        )
    }

    // ── 3. 内容保底：成员必须已各自落库（即使聚合推送全失败也不丢内容） ──────

    @Test
    fun mergeMembersAreBroadcastBeforeEnqueue_soContentIsPersisted() {
        // 关键顺序：sendBroadcast（写 HistoryCache + 广播 Flutter 入库）必须**先于** append。
        // ⚠ 必须把搜索范围限定在 Merge 分支内：全文件 indexOf 会命中前面 Push/Record 分支的
        //   sendBroadcast（首次实现即踩此坑），得出错误结论。
        val branchStart = service.indexOf("is RuleEngine.Decision.Merge ->")
        assertTrue("应存在 Merge 分支", branchStart >= 0)
        // 分支体到下一个 Decision 分支为止
        val nextBranch = service.indexOf("RuleEngine.Decision.Push ->", branchStart)
        val branch = service.substring(branchStart, if (nextBranch > 0) nextBranch else service.length)

        val idxBroadcast = branch.indexOf("webhookSender.sendBroadcast(info)")
        val idxAppend = branch.indexOf("mergePushManager.append(")
        assertTrue("Merge 分支应有 sendBroadcast", idxBroadcast >= 0)
        assertTrue("Merge 分支应有 append", idxAppend >= 0)
        assertTrue(
            "先落库再入队：Merge 分支内 sendBroadcast 必须出现在 append 之前（" +
                "否则进程在入队后、落库前被杀，该通知内容彻底丢失）",
            idxBroadcast < idxAppend
        )
    }

    @Test
    fun historyCacheIsPersistedSynchronously() {
        // 广播链路内同步写盘（进程被杀也不丢），是内容保底的底层保证。
        val cache = src("android/app/src/main/kotlin/com/fnthink/notice/HistoryCache.kt")
        assertTrue(
            "sendBroadcast 内必须写 HistoryCache（离线兜底）",
            webhook.contains("HistoryCache.append(context, json)")
        )

        // ⚠ 首版实现写成 `cache.contains("同步写盘") || cache.contains("commit()")`，
        //   被植入「同步写盘→异步写盘」时**未捕获**（`||` 让 commit() 单方面兜住了）。
        //   弱断言的典型形态：只要有一个 token 还在就永远为真。
        //   改为结构化断言：writeArray 必须用 commit()（同步落盘），绝不能用 apply()（异步）。
        val writeArray = functionBody(cache, "private fun writeArray(")
        assertTrue(
            "writeArray 必须调用 commit() 同步落盘（apply() 是异步，进程被杀会丢数据）",
            writeArray.contains(".commit()")
        )
        assertFalse(
            "writeArray 不得使用 apply()（异步落盘无法保证「入队前已持久化」这一内容保底前提）",
            writeArray.contains(".apply()")
        )

        // append() 的两条写入路径（更新已存在 / 追加新记录）都必须走 writeArray，
        // 否则会出现「某条分支只在内存里改了数组、没落盘」的静默丢失。
        val append = functionBody(cache, "fun append(")
        assertTrue(
            "append 内必须至少两次 writeArray 调用（id 去重更新路径 + 追加新记录路径）",
            Regex("writeArray\\(").findAll(append).count() >= 2
        )
        assertFalse(
            "append 内不得自行裸调 prefs.edit()（绕过 writeArray 即绕过 commit 保证）",
            append.contains("prefs.edit()")
        )
    }

    @Test
    fun failedRecordsAreManualRetryable() {
        // 最后一道兜底：历史记录「现在推送」可绕过暂停开关强制补推
        val pushNow = functionBody(service, "private fun pushRecordNow(")
        assertTrue("手动补推必须 force=true（绕过推送暂停开关）", pushNow.contains("force = true"))
        assertTrue(
            "手动补推要同时补 webhook 与邮件",
            pushNow.contains("sendWebhooksOnly") && pushNow.contains("dispatchEmail")
        )
        assertTrue(
            "Dart 侧 pushRecordNow 必须重置为 pending（否则历史里仍显示失败）",
            notifService.contains("_buildInitialDeliveries(_getActiveChannels())")
        )
    }

    // ── 4. 队列成长与恢复边界 ─────────────────────────────────────────────

    @Test
    fun overflowGroupIsPushedNotDropped() {
        val body = functionBody(mergeManager, "fun append(")
        assertTrue("超限组必须返回给调用方补推，不能丢弃", body.contains("overflowed"))
        assertFalse("append 内不得直接丢弃超限组", body.contains("continue"))
        // 调用方必须真的推送返回值
        assertTrue(
            "Service 必须推送 append 返回的溢出组",
            service.contains("for (overflow in mergePushManager.append(")
        )
    }

    @Test
    fun expiredGroupsSurviveRestart_andAreRescheduled() {
        val body = functionBody(mergeManager, "fun rescheduleAll()")
        assertFalse(
            "rescheduleAll 不得丢弃过期组（与 DelayedPushManager 策略不同：聚合组里是未推送通知）",
            body.contains("filter {") || body.contains("removeAll")
        )
        assertTrue("必须有重排闹钟调用", body.contains("scheduleNext()"))
        assertTrue("Service 启动时必须调用 rescheduleAll", service.contains("mergePushManager.rescheduleAll()"))
    }

    @Test
    fun itemCapKeepsFreshest_notOldest() {
        // 组内成员上限：必须丢弃**最旧**的，保留最新的（旧信息价值低）
        val body = functionBody(mergeManager, "fun append(")
        assertTrue(
            "组内超限应移除 index 0（最旧）后追加最新",
            body.contains("1 until items.length()")
        )
    }

    // ── 5. 网络层重试边界（说明「自动重试只到 HTTP 层」） ──────────────────

    @Test
    fun networkLayerRetriesAreBounded_soExhaustedFailureIsFinal() {
        assertTrue("网络层有有限重试", network.contains("MAX_RETRIES"))
        assertTrue(
            "重试耗尽后必须回传失败结果（不吞掉）",
            network.contains("重试耗尽") && network.contains("onResult?.invoke")
        )
        // 不可重试的失败要立即回传（如 4xx 业务失败）
        assertTrue("不可重试的失败立即回传", network.contains("if (!result.retryable)"))
    }

    @Test
    fun retryServiceDartQueueIsNotWiredIntoMergePath() {
        // 事实核查：Dart RetryService 的 addFailedNotification 目前**零调用点**，
        // 即失败推送的持久化重试队列是"有实现未接线"的状态。
        // 本断言把这个事实钉住：若将来接线，必须同步更新文档，避免文档继续声称"有自动重试"。
        val retry = src("lib/services/retry_service.dart")
        assertTrue("RetryService 存在 addFailedNotification", retry.contains("addFailedNotification"))

        val dartFiles = File("$root/lib").walkTopDown()
            .filter { it.isFile && it.extension == "dart" }
            .toList()
        val callSites = dartFiles.count { f ->
            f.readText().let { t ->
                // 排除定义文件自身
                f.name != "retry_service.dart" && t.contains("addFailedNotification(")
            }
        }
        val nativeCallSites = File("$root/android/app/src/main/kotlin").walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .count { it.readText().contains("addFailedNotification") }

        assertEquals(
            "RetryService.addFailedNotification 仍无调用点（未接线）。" +
                "若此处失败说明已接线——请同步更新 base.md 与 MergePushManager 头注释中" +
                "「聚合推送失败无自动重试」的表述。",
            0,
            callSites + nativeCallSites
        )
    }

    // ── 工具：按大括号配对提取函数体 ─────────────────────────────────────

    private fun functionBody(source: String, signature: String): String {
        val start = source.indexOf(signature)
        require(start >= 0) { "未找到函数签名: $signature" }
        val braceStart = source.indexOf('{', start)
        require(braceStart >= 0) { "函数无函数体: $signature" }
        var depth = 0
        var i = braceStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(braceStart, i + 1)
                }
            }
            i++
        }
        error("函数体大括号不配对: $signature")
    }
}
