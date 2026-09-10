package com.fnthink.notice

import com.fnthink.notice.WebhookResponseParser.DeliveryStatus
import com.fnthink.notice.WebhookResponseParser.ParseResult
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 聚合推送送达结果映射单元测试（纯逻辑，JVM 直测）。
 *
 * 守住的核心语义：**聚合推送失败绝不能被标成"已合并推送"**。
 *
 * 历史缺陷：`MergePushManager.forceFlush`（已随「锁内不做网络 IO」重构移除，兜底推送现走
 * `NotificationMonitorService.flushMergedGroup`）与 merge 到点分支都无条件构造
 * `ParseResult(SUCCESS, 0, mergeDeliveredLabel(), false)` 回传，
 * 于是 webhook 实际失败时成员记录仍显示"已合并推送"——用户以为内容已送达，
 * 而实际丢了。这类"假成功"比直接报失败危险得多：它不报错、不重试、用户不知情。
 *
 * 本组用例锁定两条不变量：
 * 1. 成功 → 文案换成 mergeDeliveredLabel()（用户需知道这是聚合推送的一部分）；
 * 2. 失败 → **保留原状态与原消息**，绝不改写成成功。
 */
class MergeDeliveryResultTest {

    private val allStatuses = DeliveryStatus.values()

    private fun result(status: DeliveryStatus) = ParseResult(status, 200, "原始消息", false)

    // ===== 不变量 1：只有 SUCCESS 才算成功 =====

    @Test
    fun onlySuccessCountsAsSuccess() {
        assertTrue(isSuccess(DeliveryStatus.SUCCESS))
        for (status in allStatuses) {
            if (status == DeliveryStatus.SUCCESS) continue
            assertFalse(
                "状态 $status 不得被判定为成功（会把失败静默成\"已合并推送\"）",
                isSuccess(status)
            )
        }
    }

    // ===== 不变量 2：失败时状态与消息都不许被改写 =====

    @Test
    fun failureStatusIsNeverRewrittenToSuccess() {
        for (status in allStatuses) {
            if (status == DeliveryStatus.SUCCESS) continue
            val forwarded = forward(result(status))
            assertEquals(
                "状态 $status 被改写：失败会静默成假成功",
                status,
                forwarded.status
            )
        }
    }

    @Test
    fun failureMessageIsPreserved() {
        for (status in allStatuses) {
            if (status == DeliveryStatus.SUCCESS) continue
            val forwarded = forward(result(status))
            assertEquals(
                "状态 $status 的失败原因被改写，用户看不到为何失败",
                "原始消息",
                forwarded.message
            )
        }
    }

    @Test
    fun successMessageIsReplacedWithMergeLabel() {
        val forwarded = forward(result(DeliveryStatus.SUCCESS))
        assertEquals(DeliveryStatus.SUCCESS, forwarded.status)
        assertEquals(I18n.mergeDeliveredLabel(), forwarded.message)
    }

    @Test
    fun retryableFlagIsPreserved() {
        val retryable = ParseResult(DeliveryStatus.NETWORK_FAIL, 0, "timeout", true)
        val forwarded = forward(retryable)
        assertTrue("可重试标记丢失会让上层无法补推", forwarded.retryable)
        assertEquals(DeliveryStatus.NETWORK_FAIL, forwarded.status)

        val nonRetryable = ParseResult(DeliveryStatus.BIZ_FAIL, 200, "errcode!=0", false)
        assertFalse(forward(nonRetryable).retryable)
    }

    @Test
    fun httpCodeIsPreserved() {
        val r = ParseResult(DeliveryStatus.HTTP_FAIL, 502, "Bad Gateway", true)
        assertEquals(502, forward(r).httpCode)
    }

    // ===== 多通道「最差优先」汇总 =====

    @Test
    fun worstResultWinsInMultiChannelAggregation() {
        // 一个成功 + 一个失败 → 整体必须判失败（不能让成功通道掩盖失败）
        val mixed = listOf(
            result(DeliveryStatus.SUCCESS),
            result(DeliveryStatus.NETWORK_FAIL)
        )
        assertEquals(
            "成功通道掩盖了失败通道：用户会以为全部送达",
            DeliveryStatus.NETWORK_FAIL,
            worstOf(mixed).status
        )
    }

    @Test
    fun allSuccessAggregatesToSuccess() {
        val all = listOf(result(DeliveryStatus.SUCCESS), result(DeliveryStatus.SUCCESS))
        assertEquals(DeliveryStatus.SUCCESS, worstOf(all).status)
    }

    @Test
    fun worstOfIsOrderIndependent() {
        val ascending = listOf(
            result(DeliveryStatus.SUCCESS),
            result(DeliveryStatus.BIZ_FAIL),
            result(DeliveryStatus.NETWORK_FAIL)
        )
        val descending = ascending.reversed()
        assertEquals(
            "汇总结果不应依赖通道返回顺序",
            worstOf(ascending).status,
            worstOf(descending).status
        )
    }

    @Test
    fun severityOrderingIsStrictAndComplete() {
        // 严重度必须覆盖全部状态且两两不同（否则「最差优先」会出现平局歧义）
        val severities = allStatuses.map { severity(it) }
        assertEquals(
            "状态严重度存在重复，最差优先汇总会产生歧义",
            allStatuses.size,
            severities.toSet().size
        )
        assertTrue(
            "SUCCESS 必须是最轻的（否则成功会被选为最差结果）",
            severity(DeliveryStatus.SUCCESS) < severity(DeliveryStatus.BIZ_FAIL)
        )
        assertTrue(
            "网络失败应重于业务失败（可重试且通常瞬时）",
            severity(DeliveryStatus.NETWORK_FAIL) > severity(DeliveryStatus.BIZ_FAIL)
        )
    }

    /**
     * `PAUSED` 的严重度必须低于**一切真实失败**。
     *
     * 语义依据：`PAUSED` 表示「用户主动暂停推送」，是用户预期行为而非错误。
     * 若把它提升到 BIZ_FAIL 之上，多通道汇总时会显示成「推送失败」，误导用户以为
     * 系统故障；更严重的是 Dart 侧依赖 `normalized == 'paused'` 来决定**不写送达日志**，
     * 一旦暂停被当成最差结果，就会把"用户暂停"污染进 webhook_delivery_log。
     *
     * 注：`PAUSED` 由 NetworkClient 在全局开关下对每个通道一致返回，正常不存在
     * 「部分暂停部分失败」的混合场景；本断言保护的是该混合场景下「失败优先于暂停」。
     */
    @Test
    fun pausedIsLessSevereThanEveryRealFailure() {
        val realFailures = allStatuses.filter {
            it != DeliveryStatus.SUCCESS && it != DeliveryStatus.PAUSED
        }
        assertTrue("真实失败状态集不应为空", realFailures.isNotEmpty())
        for (failure in realFailures) {
            assertTrue(
                "PAUSED 的严重度(${severity(DeliveryStatus.PAUSED)}) 必须低于 " +
                    "真实失败 $failure(${severity(failure)}) —— " +
                    "否则「用户暂停」会被失败掩盖显示成推送失败，并污染送达日志",
                severity(DeliveryStatus.PAUSED) < severity(failure)
            )
        }
    }

    /**
     * 混合场景回归：多通道「部分暂停 + 部分失败」时，汇总结果必须是**失败**而非暂停
     * ——用户需要知道有通道真的出错了。
     */
    @Test
    fun pausedMixedWithFailureAggregatesToFailure() {
        val mixed = listOf(result(DeliveryStatus.PAUSED), result(DeliveryStatus.NETWORK_FAIL))
        assertEquals(
            "暂停与失败混合时，汇总必须取失败（更严重者）",
            DeliveryStatus.NETWORK_FAIL,
            worstOf(mixed).status
        )
    }

    /** 纯暂停场景：所有通道一致暂停时，汇总仍为暂停（不应升级为失败） */
    @Test
    fun allPausedAggregatesToPaused() {
        val allPaused = List(3) { result(DeliveryStatus.PAUSED) }
        assertEquals(
            "全部通道都暂停时，汇总应为暂停而非失败",
            DeliveryStatus.PAUSED,
            worstOf(allPaused).status
        )
    }

    // ---- 与生产实现保持镜像的纯函数（生产侧为私有成员，此处按同一规则复刻并断言）----
    //
    // ⚠ 若修改 MergePushManager.markMembersDelivered 或 WebhookSender.severity，
    // 必须同步修改本文件的 forward/worstOf/severity —— 两边语义漂移会让本组用例
    // 变成"测试通过但生产代码已错"的假保护。

    private fun isSuccess(status: DeliveryStatus) = status == DeliveryStatus.SUCCESS

    /** 镜像 MergePushManager.markMembersDelivered 的文案改写规则 */
    private fun forward(r: ParseResult): ParseResult =
        if (isSuccess(r.status)) r.copy(message = I18n.mergeDeliveredLabel()) else r

    /** 镜像 WebhookSender.severity */
    private fun severity(status: DeliveryStatus): Int = when (status) {
        DeliveryStatus.SUCCESS -> 0
        DeliveryStatus.PAUSED -> 1
        DeliveryStatus.BIZ_FAIL -> 2
        DeliveryStatus.HTTP_FAIL -> 3
        DeliveryStatus.RATE_LIMITED -> 4
        DeliveryStatus.NETWORK_FAIL -> 5
    }

    /** 镜像 WebhookSender 的「最差优先」汇总 */
    private fun worstOf(results: List<ParseResult>): ParseResult =
        results.maxByOrNull { severity(it.status) } ?: ParseResult(
            DeliveryStatus.BIZ_FAIL, 0, "未配置 Webhook 通道", false
        )
}
