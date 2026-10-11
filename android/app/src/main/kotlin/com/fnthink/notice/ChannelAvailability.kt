package com.fnthink.notice

import android.content.Context
import org.json.JSONObject

/**
 * 通道「此刻能不能推」的原生视图（T12 B）。
 *
 * ## 为什么不需要"同步点"
 * Dart 侧 `ChannelHealthStore` 把每条通道最近一次探测结果写在 SharedPreferences，
 * 键 `channel_health_<family>:<id>`；Flutter 的 SharedPreferences 就落在本进程可读的
 * **`FlutterSharedPreferences`** 文件里，而 `ConfigManager` 本来就在读同一份文件的通道配置。
 * ⇒ 原生直接读那批键即可，不需要新增"把健康度推给原生"的方法（那会造出第二份真相）。
 *
 * ## 为什么还要自己数失败次数
 * Dart 那份只存**最近一次**结果，说不出"连着错了几次"。而 roadmap 定的"不可用"包含
 * 「连续失败 ≥3」——只有发送现场知道每一次结果，所以这一维由原生自己记账（[noteResult]），
 * 存在自己的 prefs 文件里，不污染 Dart 的键空间。
 *
 * ## 那"连着成功了几次"为什么不也在原生数（T135）
 * 同一件事有两个作者会立刻分叉：探测是 Dart 写的，而原生只在**有人来路由**时才看得见那份
 * 记录 —— 在原生数"我见到几次成功"会把"通知来得勤不勤"混进证据里（同样的探测结果，
 * 通知多的设备切回快、通知少的永远切不回）。成功次数因此在写记录那一次算好（Dart
 * `ChannelHealthStore.record` 同时看得见旧值与新值），原生只读不算 —— 见 [HealthRecord.okSuccesses]。
 *
 * ## 缓存说明（别踩）
 * 每次判定都直接读 prefs，不加进程内缓存：Dart 写入同一份 prefs 时原生侧的
 * `SharedPreferences` 实例不会自动失效，缓存下来就会拿到过期结论 —— 而"过期但看起来正常"
 * 正是这条链路最坏的错误方向。文件很小（每条通道一个键），读的代价可以忽略。
 */
object ChannelAvailability {

    /** 与 Dart `ChannelHealthStore.staleness` 同口径：超过 6 小时的成功不能证明现在通 */
    const val STALENESS_MS = 6L * 60L * 60L * 1000L

    /** 连续失败到这个数就判不可用（roadmap T12 定的阈值） */
    const val FAILURE_THRESHOLD = 3

    private const val FAILS_PREFS = "channel_send_fails"
    private const val FAILS_KEY_PREFIX = "fails_"

    /** 判定原因。`isAvailable` 只认 [FRESH_SUCCESS]，其余都算"不可用"。 */
    enum class Reason {
        FRESH_SUCCESS,
        FRESH_FAILURE,
        STALE_SUCCESS,
        NEVER_PROBED,
        CONSECUTIVE_FAILURES,
        ;

        /** 只有"最近成功且没过时效"才认为可用 */
        val isAvailable: Boolean get() = this == FRESH_SUCCESS
    }

    /**
     * Dart 健康记录里我们关心的三个字段（latency/httpCode 对路由没有意义，不读）。
     *
     * [okSuccesses] 是「这条记录是第几次连续成功探测」——**计数住在 Dart 那一侧**
     * （`ChannelHealthStore.record` 写新记录时按旧记录算出来），原因见下面 [readHealth]：
     * 只有写的那一次同时看得见旧值与新值，而原生在路由现场反复读到同一份记录时
     * 并不能分辨"这是第几次看见它"。
     */
    data class HealthRecord(
        val reachable: Boolean,
        val probedAt: Long,
        val okSuccesses: Int = 0,
    )

    /**
     * 纯判定（JVM 直测，不碰 Android API）：
     * 连续失败**优先于**任何成功记录 —— 用户能立刻看到的症状是"最近一直在失败"，
     * 这时即便缓存里还挂着一条早前的成功，也不该继续占用主通道。
     */
    fun reasonOf(fails: Int, record: HealthRecord?, nowMs: Long): Reason {
        if (fails >= FAILURE_THRESHOLD) return Reason.CONSECUTIVE_FAILURES
        if (record == null) return Reason.NEVER_PROBED
        if (!record.reachable) return Reason.FRESH_FAILURE
        if (nowMs - record.probedAt > STALENESS_MS) return Reason.STALE_SUCCESS
        return Reason.FRESH_SUCCESS
    }

    fun keyOf(family: String, id: String) = "$family:$id"

    /**
     * 读 Dart 写的健康记录；键不存在 / 值坏 → null（= 从没探测过）
     *
     * ⚠ 这一族**降级锁存期间照新**：探测候选取的是各服务那个 `probeTargets`，它只看
     * `enabled` 与有没有 URL，从不按角色筛（T135 的 release 判据靠的就是这一点 ——
     * 锁存期主通道不再被发送，发送侧记账从此没有新读数，唯一还在长读数的就是这里）。
     */
    fun readHealth(context: Context, family: String, id: String): HealthRecord? {
        val raw = context
            .getSharedPreferences(ConfigManager.FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
            .getString("flutter.$KEY_HEALTH_PREFIX${keyOf(family, id)}", null) ?: return null
        return try {
            val obj = JSONObject(raw)
            HealthRecord(
                reachable = obj.optBoolean("reachable", false),
                probedAt = obj.optLong("probedAt", 0L),
                // 旧记录没有这个字段 ⇒ 0：说不出"第几次连续成功"就是没证据，
                // 而"没证据"在切回那一侧的正确表现是不切回，不是切回。
                okSuccesses = obj.optInt("okSuccesses", 0),
            )
        } catch (e: Exception) {
            // 坏值按"没记录"处理：一次 JSON 解析失败不该把整条通道判成可用或不适用，
            // 交给 NEVER_PROBED 走同一条兜底路径（原生侧解析容错的统一做法）
            null
        }
    }

    /**
     * 一条通道**这一轮**的两把尺子。
     *
     * ⚠ 为什么必须有第二把（[recovery]），而不是直接拿 [available] 去判"主又可用了"：
     * [available] 里含发送侧那个连续失败计数（[FAILURE_THRESHOLD]），而**锁存期间主通道
     * 不再被发送** ⇒ 那份计数再也不会归零 ⇒ 若用它当切回条件，条件永远不成立，
     * 这一族就成了"锁上就再没有自动出口"——正是 T135 要修的那件事。
     * 所以切回只看探测侧那一条链（[recovery]），而失败计数只在真的切回时由
     * [BackupModeStore.release] 清掉。
     *
     * 三个数一次读齐：调用方要的判据是「可用 / 探测新鲜 / 降级之后新写 / 连续成功够了数」，
     * 分几次读 prefs 就会出现"可用性是新的、计数是旧的"那种半份读数。
     * 这里也没有进程内缓存，理由与文件头那条一样。
     */
    data class Read(
        val available: Boolean,
        val recovery: ChannelRouting.Recovery?,
    )

    fun observe(context: Context, family: String, id: String, nowMs: Long): Read = readOf(
        fails = failsOf(context, family, id),
        record = readHealth(context, family, id),
        nowMs = nowMs,
    )

    /**
     * [observe] 的那一份**纯**算法（JVM 直测，不碰 prefs）。
     *
     * ⚠ 这一条必须可测：两把尺子的差就是"发送侧的失败计数只压 available，不压 recovery" ——
     * 若它跟着被压掉，锁存期那份探测证据永远说不出"可用"，自动切回就成了死锁
     * （条件永远不成立，而屏幕上没有任何异常）。那种形状在真机上看起来完全正常。
     */
    fun readOf(fails: Int, record: HealthRecord?, nowMs: Long): Read = Read(
        available = reasonOf(fails = fails, record = record, nowMs = nowMs).isAvailable,
        // fails 传 0 = "只看这份探测记录说不说得通"，发送侧那把悲观计数不参与（见 Read 的注释）
        recovery = record?.let {
            ChannelRouting.Recovery(
                fresh = reasonOf(0, it, nowMs).isAvailable,
                probedAt = it.probedAt,
                okSuccesses = it.okSuccesses,
            )
        },
    )

    fun failsOf(context: Context, family: String, id: String): Int =
        failsPrefs(context).getInt(FAILS_KEY_PREFIX + keyOf(family, id), 0)

    /** 每个通道的发送结果都过这里一次：成功清零、失败累加 */
    fun noteResult(context: Context, family: String, id: String, success: Boolean) {
        if (id.isEmpty()) return
        val key = FAILS_KEY_PREFIX + keyOf(family, id)
        val prefs = failsPrefs(context)
        val next = if (success) 0 else prefs.getInt(key, 0) + 1
        if (next == 0) prefs.edit().remove(key).apply()
        else prefs.edit().putInt(key, next).apply()
    }

    /** 切回主通道（自动或手动）时清掉失败计数，否则一放开就又被判"不可用" */
    fun clearAllFailures(context: Context) {
        val prefs = failsPrefs(context)
        prefs.edit().clear().apply()
    }

    private fun failsPrefs(context: Context) =
        context.getSharedPreferences(FAILS_PREFS, Context.MODE_PRIVATE)

    /** Dart `ChannelHealthStore.keyPrefix` 的镜像常量（跨端契约，由守卫比对） */
    const val KEY_HEALTH_PREFIX = "channel_health_"
}

/**
 * 「备用模式已启用」的锁存（T12），以及那枚"主不可用时是否自动切备"的开关（T135）。
 *
 * ## 为什么要锁存
 * 主通道在两个失败之间往往时好时坏，每条通知重新判断会让用户在主备之间反复收（抖动）。
 * 所以一旦降级就**保持**。
 *
 * ## 但保持不等于永远不解除（T135）
 * 老写法是"只有用户手动切回才解除"，代价是：主通道修好了，这台设备却永远按备用档推，
 * 而用户必须自己想起来点那一枚按钮。现在解除有两条路：手动那一枚照旧，
 * 自动那一条由 [ChannelRouting.route] 判 —— 要的是**降级之后新写的、且自己连着第
 * [ChannelRouting.RECOVERY_SUCCESS_COUNT] 次成功**的那一份探测读数（一次成功就切就是把
 * 注释点名的抖动原样放回来，而"降级之前就已经连着成功过"也不算证据）。
 * 判据仍然只有一个作者：本文件不判"该不该切"，只把决策落盘（[applyDecision]），
 * 并在降级那一刻记下时间戳（[KEY_ENGAGED_AT]）—— 上面那个"之后"要的就是它。
 *
 * ## 为什么写口在这里而不是各链自己写
 * [engage]/[release] 只由 [applyDecision] 调用，而两条链（通知转发、短信／来电）都只调
 * [applyDecision] 一次。两条链一条写、一条不写的话，"这台到底切没切备用"就变成
 * 随哪条链先跑而变的东西。
 *
 * ## 存在哪里
 * 原生自有的 prefs 文件（不放 `FlutterSharedPreferences`）：那份文件由 Dart 写，
 * 原生侧已加载的 SharedPreferences 实例不会随 Dart 写入自动失效，缓存会读到过期值。
 * 唯一的例外是 [KEY_AUTO_BACKUP] —— 那是**用户的选择**，作者只能是 Dart 那一侧的开关，
 * 这里只读（缺省 true：今天的行为本来就是自动切备，把既有行为藏进一个默认关的开关里，
 * 表现就是"升级之后我的通知怎么不切了"）。
 */
object BackupModeStore {
    private const val PREFS = "channel_send_fails"
    private const val KEY_ENGAGED = "backup_engaged"

    /** 切回留痕：状态页要能说出"什么时候、凭什么"回来的（T135 验收③） */
    private const val KEY_RELEASED_AT = "backup_released_at"
    private const val KEY_RELEASED_AUTO = "backup_released_auto"

    /** 降级时刻：自动切回要的"那份读数是降级**之后**新写的"，靠的就是这一个数 */
    private const val KEY_ENGAGED_AT = "backup_engaged_at"

    /**
     * Dart 那枚「主通道不可用时自动切到备用通道」开关的键（带 `flutter.` 前缀：
     * 读的是 `FlutterSharedPreferences`）。键名与默认值由守卫与 Dart 侧比对，
     * 见 `test/architecture/auto_backup_default_test.dart`。
     */
    const val KEY_AUTO_BACKUP = "flutter.channel_auto_backup"

    /** 一次切回的留痕 */
    data class Release(val at: Long, val auto: Boolean)

    fun isEngaged(context: Context): Boolean =
        prefs(context).getBoolean(KEY_ENGAGED, false)

    /**
     * 这一轮锁存是什么时候开始的（判"那份探测读数是降级**之后**写的"要用）。
     *
     * 老数据（升级前就锁着的）没有这个键 ⇒ 返回 0 = "很久以前就锁上了"，
     * 于是它的第一份新成功读数就能把锁存解开 —— 方向是"修好就放人"，
     * 而不是"升级之后这台永远按备用档推"。
     */
    fun engagedAt(context: Context): Long = prefs(context).getLong(KEY_ENGAGED_AT, 0L)

    /**
     * 最近一次切回（自动或手动）。没切回过、或那段留痕已经**超过时效** → null。
     *
     * 为什么要有时效这一刀：状态页那句"已回到主通道"是**状态**不是历史 ——
     * 一条八十小时前的切回还在屏幕上挂着，用户读到的就是"这台现在不太对"，
     * 而屏幕上早就没有那件事了。用的尺与健康度同一把（[ChannelAvailability.STALENESS_MS]）。
     * 下一次降级也会把它抹掉（[engage]）。
     */
    fun lastRelease(context: Context): Release? {
        val p = prefs(context)
        val at = p.getLong(KEY_RELEASED_AT, 0L)
        if (at <= 0L) return null
        if (System.currentTimeMillis() - at > ChannelAvailability.STALENESS_MS) return null
        return Release(at = at, auto = p.getBoolean(KEY_RELEASED_AUTO, false))
    }

    /** 那枚开关：关掉 ⇒ 本轮仍按当轮判据走，但**绝不写 [KEY_ENGAGED]**（见 [applyDecision]） */
    fun autoBackupEnabled(context: Context): Boolean = context
        .getSharedPreferences(ConfigManager.FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
        .getBoolean(KEY_AUTO_BACKUP, true)

    fun engage(context: Context) {
        prefs(context).edit()
            .putBoolean(KEY_ENGAGED, true)
            // 新的降级开始一段新故事：上一段"已回到主通道"那句话不能再挂着
            .remove(KEY_RELEASED_AT).remove(KEY_RELEASED_AUTO)
            .putLong(KEY_ENGAGED_AT, System.currentTimeMillis())
            .apply()
    }

    /**
     * 解除锁存。[auto] = 由路由判据自动切的（连续探测成功），false = 用户手动切回。
     *
     * 两种都要顺带清掉失败计数，否则一放开就又被判"不可用"。
     */
    fun release(context: Context, auto: Boolean) {
        prefs(context).edit()
            .remove(KEY_ENGAGED).remove(KEY_ENGAGED_AT)
            .putLong(KEY_RELEASED_AT, System.currentTimeMillis())
            .putBoolean(KEY_RELEASED_AUTO, auto)
            .apply()
        ChannelAvailability.clearAllFailures(context)
    }

    /** 这一轮对那份锁存该做什么（纯函数，JVM 直测） */
    enum class LatchChange { None, Engage, Release }

    /**
     * 落盘裁决：**只在状态真的变化时**才动盘。
     *
     * 为什么需要这第三份判断（路由已经说了 engagedBackup/releasedBackup）：`engagedBackup`
     * 在锁存期每一轮都是 true、`releasedBackup` 在开关关掉后每一轮都是 true —— 直接照着写
     * 就成了每条通知一次无意义的磁盘写，而写 `backup_released_at` 会把"什么时候回来的"
     * 那个时刻一路刷成现在。
     */
    fun latchChange(engaged: Boolean, decision: ChannelRouting.Decision): LatchChange = when {
        decision.releasedBackup && engaged -> LatchChange.Release
        decision.engagedBackup && !engaged -> LatchChange.Engage
        else -> LatchChange.None
    }

    /**
     * 把一轮路由决策落到锁存位上（**唯一的写口**，两条链共用）。
     * 判据本身在 [latchChange]，那里可 JVM 直测；这里只认那一个结果。
     */
    fun applyDecision(context: Context, engaged: Boolean, decision: ChannelRouting.Decision) {
        when (latchChange(engaged, decision)) {
            LatchChange.Engage -> engage(context)
            LatchChange.Release -> release(context, auto = true)
            LatchChange.None -> Unit
        }
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
