package com.fnthink.notice

/**
 * 主备路由决策（T12 B，T135 补自动切回与那枚开关）。**纯函数**：不碰 prefs / 网络 / Context，
 * 因此可以 JVM 直测（仿 `ChannelDispatch.kt` 的先例）。调用方负责把
 * 「谁是主、谁可用、探测那一条尺子怎么说、锁存从什么时候开始」查好喂进来。
 *
 * ## 规则（逐条对应下面的测试）
 * 1. `NONE`（不参与）永不进候选；
 * 2. 有可用主通道 → 只推主通道；
 * 3. 主通道都不可用 **且** 存在可用备用 → 推备用，并**锁存**；
 * 4. 锁存期间也绝不丢弃：备用全不可用就退回可用主通道，再不行就推全部候选 ——
 *    "不静默丢失"是比"严格照判据"更高优先级的既有约束；
 * 5. 压根没配主通道（全设成备用/不参与）不算降级，不锁存；
 * 6. `UNSET`（用户还没指定过主/备，新建通道的起点）**既不进主档也不进备用档**：
 *    有可用主通道时不推它（同一条通知不再跟着全量重复推），而一条主都没设时它会随
 *    规则 4 的兜底一起推 ⇒ "没人设主就一条都发不出去"这种静默丢失不可能出现。
 * 7. **锁存期间，主通道的探测证据攒够了就自动切回**（T135 ②）。要同时满足三件，
 *    少一件都不算（每件一条用例，见 [Recovery]）：那份读数**新鲜**、它是**降级之后**新写的、
 *    而它自己是**连续第 [RECOVERY_SUCCESS_COUNT] 次**成功。一次成功就切 = 把
 *    `BackupModeStore` 原话点名的抖动原样放回来，而且比老行为更吵。
 * 8. 那枚「主不可用时自动切备」的开关（T135 ③，缺省开）关掉时：**当轮仍按 1–6 判该推谁，
 *    但 [Decision.engagedBackup] 永远不置起**（"关掉后绝不写 `backup_engaged`"就落在这一个
 *    return 上），而已经锁着的那一份当轮就解除（[Decision.releasedBackup]）—— 留着它，
 *    状态页那句"已切到备用"就不再是这台设备的真相。
 */
object ChannelRouting {

    /** [key] 是 `family:id`，与 [ChannelAvailability.keyOf] 同形 */
    data class Member(
        val key: String,
        val role: ChannelRole,
        val available: Boolean,
        /** 探测侧那把尺子（[7] 的证据）。null = 这条通道一份探测记录都没有 */
        val recovery: Recovery? = null,
    )

    /**
     * 一条通道的自动切回证据，全部来自**探测**那一条链（Dart 写的健康记录）。
     *
     * ⚠ 为什么不用 [available]：`available` 含发送侧的连续失败计数，而锁存期主通道不再被发送
     * ⇒ 那个计数永远不会归零 ⇒ 用它当条件等于"锁上就没有自动出口"。
     * 原话与推导写在 `ChannelAvailability.Read` 的注释里，那一处是唯一的解释处。
     *
     * @param fresh 这份读数没过时效（`STALENESS_MS`）且 `reachable`
     * @param probedAt 读数写下的时刻（用来判"是不是降级之后新写的"）
     * @param okSuccesses 这是这条通道连续第几次成功探测（计数在写记录那一次算好，见同处注释）
     */
    data class Recovery(val fresh: Boolean, val probedAt: Long, val okSuccesses: Int)

    /**
     * 自动切回要攒够几次连续成功探测。与"连续失败到 [ChannelAvailability.FAILURE_THRESHOLD]
     * 就降级"对称：出去与回来都要那么多证据，否则降级慢、切回快，抖动正是从这个不对称长出来的。
     */
    const val RECOVERY_SUCCESS_COUNT = 3

    /**
     * @param keys 本次要推送的通道 key（保持传入顺序，便于日志与测试比对）
     * @param engagedBackup 本次之后「备用模式」应当处于锁存状态。
     *   **只在真的发生降级时才置 true**：没配主通道的人不该被记成"已切到备用"。
     * @param viaBackup 本轮**不是**"只推可用主通道"—— 这是给送达记录打的那个标记
     *   （历史页那句「本次走了备用」）。它与 [engagedBackup] 在真降级时同真，但**不是一件事**：
     *   T132 之前它俩是同一个字段，于是规则 4 那条兜底（"主备都判成不可用也要照推，一条不能少"）
     *   推了却不标 —— 用户看到的历史是"走了主通道"，而那次其实谁都不可用。
     *   默认跟随 [engagedBackup]，只有兜底那一档显式置 true（它标、但不锁存）。
     *   开关关掉那一档也标（规则 8：那一轮推的确实不是主档），但同样不锁存。
     * @param releasedBackup 本次之后那份锁存**不再代表任何事**，调用方要把它解除
     *   （[BackupModeStore.applyDecision]）。落盘点只有那一处，
     *   所以自动切回这件事在两条链上表现一致。
     */
    class Decision(
        val keys: List<String>,
        val engagedBackup: Boolean,
        val viaBackup: Boolean = engagedBackup,
        val releasedBackup: Boolean = false,
    )

    /**
     * @param backupEngaged 当前那份锁存
     * @param autoBackup 用户那枚「主不可用时自动切备」的开关（缺省开：今天的行为就是自动切备）
     * @param engagedAtMs 锁存开始的时刻；0 = 不知道（升级前就锁着的老数据），
     *   那一档按"很久以前锁上的"处理 ⇒ 攒够证据就放人，见 [ChannelAvailability.engagedAt]
     */
    fun route(
        members: List<Member>,
        backupEngaged: Boolean,
        autoBackup: Boolean = true,
        engagedAtMs: Long = 0L,
    ): Decision {
        // 关掉开关 ⇒ 那份锁存不再代表这台设备的真相，当轮就解除（规则 8）
        val dropLatch = backupEngaged && !autoBackup
        val eligible = members.filter { it.role != ChannelRole.NONE }
        if (eligible.isEmpty()) {
            return Decision(
                emptyList(),
                engagedBackup = backupEngaged && autoBackup,
                releasedBackup = dropLatch,
            )
        }

        val primaries = eligible.filter { it.role == ChannelRole.PRIMARY }
        val backups = eligible.filter { it.role == ChannelRole.BACKUP }
        val okPrimaries = primaries.filter { it.available }
        val okBackups = backups.filter { it.available }

        if (backupEngaged && autoBackup) {
            // 规则 7：证据攒够的那一条主通道出现 ⇒ 这一轮就回主档，并交出锁存
            val recovered = primaries.filter { it.recoveredSince(engagedAtMs) }
            if (recovered.isNotEmpty()) {
                // 切回那一轮推的就是"可用主通道"那一档，与规则 2 同一个答案；
                // viaBackup 跟着 engagedBackup=false ⇒ 历史里那句「走了备用」不再挂着。
                val keys = okPrimaries.ifEmpty { recovered }.let { keysOf(it) }
                return Decision(keys, false, releasedBackup = true)
            }
            // 规则 3+4：证据没攒够就继续锁着，但任何一档能用就用，绝不空转
            okBackups.ifNotEmpty { return Decision(keysOf(it), true) }
            okPrimaries.ifNotEmpty { return Decision(keysOf(it), true) }
            return Decision(keysOf(eligible), true)
        }

        okPrimaries.ifNotEmpty {
            return Decision(keysOf(it), false, releasedBackup = dropLatch)
        }

        if (primaries.isNotEmpty() && okBackups.isNotEmpty()) {
            // 真的降级：主通道都在、但都不可用 → 启用备用。开关开着才锁存。
            return Decision(
                keysOf(okBackups),
                engagedBackup = autoBackup,
                viaBackup = true,
                releasedBackup = dropLatch,
            )
        }
        if (primaries.isEmpty()) {
            // 规则 5：没配主通道，直接推可用的备用，不构成"切换"
            okBackups.ifNotEmpty {
                return Decision(keysOf(it), false, releasedBackup = dropLatch)
            }
        }

        // 规则 4 的另一半：拿不准就照推（例如新装后谁都没探测过，
        // 判据说"全部不可用"，但一条都不推等于丢通知 —— 那是最坏的结果）。
        // ⚠ 这一档**标 viaBackup 但不锁存**：推的不是"那几把备用"，而是全部候选，
        //   把它记成只走主通道是替用户撒谎（T132）；而它也不构成"从此以备用为准"的降级事实。
        return Decision(keysOf(eligible), false, viaBackup = true, releasedBackup = dropLatch)
    }

    /** 规则 7 那三件：新鲜、降级之后新写的、连续成功次数够了 */
    private fun Member.recoveredSince(engagedAtMs: Long): Boolean {
        val r = recovery ?: return false
        return r.fresh && r.probedAt > engagedAtMs && r.okSuccesses >= RECOVERY_SUCCESS_COUNT
    }

    private inline fun <T> List<T>.ifNotEmpty(block: (List<T>) -> Unit) {
        if (isNotEmpty()) block(this)
    }

    private fun keysOf(list: List<Member>) = list.map { it.key }
}
