package com.fnthink.notice

/**
 * 主备路由决策（T12 B）。**纯函数**：不碰 prefs / 网络 / Context，因此可以 JVM 直测
 * （仿 `ChannelDispatch.kt` 的先例）。调用方负责把「谁是主、谁可用」查好喂进来。
 *
 * ## 规则（roadmap T12 定稿，逐条对应下面的测试）
 * 1. `NONE`（不参与）永不进候选；
 * 2. 有可用主通道 → 只推主通道；
 * 3. 主通道都不可用 **且** 存在可用备用 → 推备用，并**锁存**（不自动切回，防抖动）；
 * 4. 锁存期间也绝不丢弃：备用全不可用就退回可用主通道，再不行就推全部候选 ——
 *    "不静默丢失"是比"严格照判据"更高优先级的既有约束；
 * 5. 压根没配主通道（全设成备用/不参与）不算降级，不锁存。
 */
object ChannelRouting {

    /** [key] 是 `family:id`，与 [ChannelAvailability.keyOf] 同形 */
    data class Member(val key: String, val role: ChannelRole, val available: Boolean)

    /**
     * @param keys 本次要推送的通道 key（保持传入顺序，便于日志与测试比对）
     * @param engagedBackup 本次之后「备用模式」应当处于锁存状态。
     *   **只在真的发生降级时才置 true**：没配主通道的人不该被记成"已切到备用"。
     */
    class Decision(val keys: List<String>, val engagedBackup: Boolean)

    fun route(members: List<Member>, backupEngaged: Boolean): Decision {
        val eligible = members.filter { it.role != ChannelRole.NONE }
        if (eligible.isEmpty()) return Decision(emptyList(), backupEngaged)

        val primaries = eligible.filter { it.role == ChannelRole.PRIMARY }
        val backups = eligible.filter { it.role == ChannelRole.BACKUP }
        val okPrimaries = primaries.filter { it.available }
        val okBackups = backups.filter { it.available }

        if (backupEngaged) {
            // 规则 3+4：锁存不自动解除，但任何一档能用就用，绝不空转
            okBackups.ifNotEmpty { return Decision(keysOf(it), true) }
            okPrimaries.ifNotEmpty { return Decision(keysOf(it), true) }
            return Decision(keysOf(eligible), true)
        }

        okPrimaries.ifNotEmpty { return Decision(keysOf(it), false) }

        if (primaries.isNotEmpty() && okBackups.isNotEmpty()) {
            // 真的降级：主通道都在、但都不可用 → 启用备用并锁存
            return Decision(keysOf(okBackups), true)
        }
        if (primaries.isEmpty()) {
            // 规则 5：没配主通道，直接推可用的备用，不构成"切换"
            okBackups.ifNotEmpty { return Decision(keysOf(it), false) }
        }

        // 规则 4 的另一半：拿不准就照推（例如新装后谁都没探测过，
        // 判据说"全部不可用"，但一条都不推等于丢通知 —— 那是最坏的结果）
        return Decision(keysOf(eligible), false)
    }

    private inline fun <T> List<T>.ifNotEmpty(block: (List<T>) -> Unit) {
        if (isNotEmpty()) block(this)
    }

    private fun keysOf(list: List<Member>) = list.map { it.key }
}
