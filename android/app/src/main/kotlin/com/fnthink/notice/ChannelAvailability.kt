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

    /** Dart 健康记录里我们关心的两个字段（latency/httpCode 对路由没有意义，不读） */
    data class HealthRecord(val reachable: Boolean, val probedAt: Long)

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

    /** 读 Dart 写的健康记录；键不存在 / 值坏 → null（= 从没探测过） */
    fun readHealth(context: Context, family: String, id: String): HealthRecord? {
        val raw = context
            .getSharedPreferences(ConfigManager.FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
            .getString("flutter.$KEY_HEALTH_PREFIX${keyOf(family, id)}", null) ?: return null
        return try {
            val obj = JSONObject(raw)
            HealthRecord(
                reachable = obj.optBoolean("reachable", false),
                probedAt = obj.optLong("probedAt", 0L),
            )
        } catch (e: Exception) {
            // 坏值按"没记录"处理：一次 JSON 解析失败不该把整条通道判成可用或不适用，
            // 交给 NEVER_PROBED 走同一条兜底路径（原生侧解析容错的统一做法）
            null
        }
    }

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

    /** 手动切回主通道时清掉失败计数，否则一放开就又被判"不可用" */
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
 * 「备用模式已启用」的锁存（T12）。
 *
 * 为什么要锁存：主通道在两个失败之间往往时好时坏，每条通知重新判断会让用户在
 * 主备之间反复收（抖动）。所以一旦降级就**保持**，只有用户手动切回才解除 ——
 * 也因此**锁存和切回入口必须同一个版本上线**，只上锁存等于给用户一个没有出口的开关。
 *
 * 存在原生自有的 prefs 文件里（不放 `FlutterSharedPreferences`）：那份文件由 Dart 写，
 * 原生侧已加载的 SharedPreferences 实例不会随 Dart 写入自动失效，缓存会读到过期值。
 */
object BackupModeStore {
    private const val PREFS = "channel_send_fails"
    private const val KEY_ENGAGED = "backup_engaged"

    fun isEngaged(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(KEY_ENGAGED, false)

    fun engage(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putBoolean(KEY_ENGAGED, true).apply()
    }

    /** 用户手动切回：同时清掉失败计数，否则一放开就又被判"不可用" */
    fun release(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .remove(KEY_ENGAGED).apply()
        ChannelAvailability.clearAllFailures(context)
    }
}
