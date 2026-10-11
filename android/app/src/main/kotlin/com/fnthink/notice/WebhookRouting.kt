package com.fnthink.notice

import android.content.Context

/**
 * Webhook 一族的主备路由（T132）。
 *
 * ## 为什么要有这一个文件
 * 「谁是主、谁可用、这一轮该推哪几把」原本只有一个作者：纯函数 [ChannelRouting.route]，
 * 唯一的调用者是 `NotificationMonitorService.routeChannels()`（四族合成一次决策）。
 * 但**短信与来电两条链路从来没走过它** —— 它们各自把 `getWebhookChannelConfigs()` 的
 * 全量挨个发一遍。表现就是维护者点名要查的那件事：「默认只发主通道」在这两条链上不成立
 * （主＋备同发），而且它们既不读可用性、也不记失败，于是"主通道完全不可用"这个判断
 * 对这两条链**永远不会成立**。
 *
 * ## 形状约束
 * 这个文件**不另造判据**：[select] 里只调一次 `ChannelRouting.route`，不出现第二个
 * `filter { role ... }`。它存在的意义只是把那一套判据接到 webhook 一族上，让三条链
 * （通知转发 / 短信 / 来电）读同一个答案。
 */
object WebhookRouting {

    /**
     * @param viaBackup 本轮不是"只推可用主通道" ⇒ 送达记录要打的那个标记。
     * @param engagedBackup 本轮之后设备级锁存应处于"已切备用"（调用方负责落盘，见 [routeWebhooks]）。
     * @param decision 路由决策原样带出来：落盘只认这一个对象（[BackupModeStore.applyDecision]），
     *   这里不另抄一遍"该不该写锁存"的判断 —— 抄一遍就有两个作者，而通知转发那条链
     *   已经抄过一份了（T135 把它收成一处）。
     */
    class Selection(
        val configs: List<ConfigManager.WebhookChannelConfig>,
        val decision: ChannelRouting.Decision,
    ) {
        val viaBackup: Boolean get() = decision.viaBackup
        val engagedBackup: Boolean get() = decision.engagedBackup
        val releasedBackup: Boolean get() = decision.releasedBackup
    }

    /**
     * 纯函数：给定配置、可用性读数与锁存状态，返回该推哪几把。
     *
     * 读数由调用方喂进来（[read] 收通道 id，回 [ChannelAvailability.Read]：可用性 + 探测证据）
     * ⇒ 这条链在 JVM 上可测，不必碰 prefs。
     */
    fun select(
        configs: List<ConfigManager.WebhookChannelConfig>,
        read: (String) -> ChannelAvailability.Read,
        backupEngaged: Boolean,
        autoBackup: Boolean = true,
        engagedAtMs: Long = 0L,
    ): Selection {
        val decision = ChannelRouting.route(
            configs.map {
                val r = read(it.id)
                ChannelRouting.Member(
                    key = "webhook:" + it.id,
                    role = it.role,
                    available = r.available,
                    recovery = r.recovery,
                )
            },
            backupEngaged,
            autoBackup,
            engagedAtMs,
        )
        val want = decision.keys.toHashSet()
        return Selection(
            configs.filter { ("webhook:" + it.id) in want },
            decision,
        )
    }

    /**
     * 生产装配：现读每把通道的可用性、探测证据与那一份设备级锁存，再把决策落盘 ——
     * 与 `routeChannels()` 同一个动作、同一个写口（[BackupModeStore.applyDecision]）。
     * 两条链一条写、一条不写的话，"这台到底切没切备用"就变成随哪条链先跑而变的东西。
     */
    fun routeWebhooks(
        context: Context,
        configs: List<ConfigManager.WebhookChannelConfig>,
    ): Selection {
        val now = System.currentTimeMillis()
        val engaged = BackupModeStore.isEngaged(context)
        val selected = select(
            configs,
            read = { id -> ChannelAvailability.observe(context, "webhook", id, now) },
            backupEngaged = engaged,
            autoBackup = BackupModeStore.autoBackupEnabled(context),
            engagedAtMs = BackupModeStore.engagedAt(context),
        )
        BackupModeStore.applyDecision(context, engaged, selected.decision)
        return selected
    }
}
