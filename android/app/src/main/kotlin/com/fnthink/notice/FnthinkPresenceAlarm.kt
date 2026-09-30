package com.fnthink.notice

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 幻念推送"到点去问一次货"的闹钟（T33 第二片 / §4-9）。
 *
 * 分工要说清楚，因为这一族最容易长的就是"两处都以为对方会重排"：
 *  - **这一层只管"到点"**：什么时候到点、下一轮隔多久，唯一的读者是 Dart 侧
 *    （契约 `presence.pollIntervalSeconds` / `burstWhenPending`）。这里**不读 interval、也不自己续排** ——
 *    Kotlin 里再存一份节奏就是第二个真值，改契约那一刀不会有任何东西报错，
 *    而表现是"手机按旧的 20 秒醒，服务器按新的 60 秒等你"。
 *  - 到点之后**不在这儿干活**：转给 [FnthinkPresenceWorker]（闹钟的 receiver 只有几秒生命周期，
 *    而起引擎 + 签名 + 取货 + 落库是几十秒的事）。
 *
 * ⚠ `REQUEST_CODE` 是新号，**不许复用**既有的那几个：`2001`（电量闹钟）、`3001`（延迟推送）、
 * `3002`（合并推送）、`3101`（小组件存活闹钟）与 `0/1/2`（PendingIntent 请求码）。
 * 同码不同 action 会互相覆盖，而被覆盖的那一类从此不再响 —— 没有任何一条日志会说"你的闹钟被谁顶掉了"。
 */
class FnthinkPresenceAlarm(private val context: Context) {

    companion object {
        private const val TAG = "FnthinkPresenceAlarm"
        const val ACTION_ROUND_DUE = "com.fnthink.notice.FNTHINK_ROUND_DUE"
        const val REQUEST_CODE = 3201
        private const val PREFS_NAME = "fnthink_presence"
        private const val KEY_NEXT_AT = "next_round_at"
        private const val KEY_CADENCE = "cadence_seconds"
    }

    private val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
    private val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 下一轮被排在什么时候（毫秒）。0 = 没排。界面/日志用它回答"到底还有没有人醒"。 */
    fun nextRoundAt(): Long = prefs.getLong(KEY_NEXT_AT, 0L)

    /**
     * Dart 上一次交下来的那一档节奏（秒）。0 = 没交过。
     *
     * 它存在的唯一理由：**链条不能在"引擎起不来"那一天断掉** —— receiver 到点之后拿它续下一轮，
     * 而数值仍是 Dart 写的（这里不自己算，也不写死一个默认值：默认值就是第二个真值）。
     */
    fun cadenceSeconds(): Long = prefs.getLong(KEY_CADENCE, 0L)

    /**
     * 排一轮。`delaySeconds <= 0` 一律**取消而不是排"现在"**：
     * 调用方给 0 通常意味着"这一路不该再醒了"（关掉了接收、或配置不全），
     * 把它翻译成"立刻再来一次"会让取消永远取消不掉。
     */
    fun schedule(delaySeconds: Long) {
        if (delaySeconds <= 0L) {
            cancel()
            return
        }
        val am = alarmManager ?: run {
            Log.w(TAG, "没有 AlarmManager：这一轮只能等前台")
            return
        }
        val fireAt = System.currentTimeMillis() + delaySeconds * 1000L
        try {
            val pi = pendingIntent()
            prefs.edit().putLong(KEY_CADENCE, delaySeconds).apply()
            // 与延迟推送那一条同一套降级：精确闹钟未授权时退到 setAndAllowWhileIdle（Doze 下分钟级偏晚），
            // 而不是抛出去 —— "收货晚一点"与"收货从此停掉"是两个后果，前者用户可以接受。
            if (exactAllowed()) {
                try {
                    am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
                    prefs.edit().putLong(KEY_NEXT_AT, fireAt).apply()
                    Log.d(TAG, "幻念收货闹钟已排 fireAt=$fireAt（精确）")
                    return
                } catch (e: SecurityException) {
                    Log.w(TAG, "精确闹钟未授权，降级非精确", e)
                }
            }
            am.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, fireAt, pi)
            prefs.edit().putLong(KEY_NEXT_AT, fireAt).apply()
            Log.d(TAG, "幻念收货闹钟已排 fireAt=$fireAt（非精确）")
        } catch (e: Exception) {
            // 排不上必须留话：否则这一路从此刻起再没人醒，而界面上看着一切正常。
            Log.e(TAG, "幻念收货闹钟排程失败", e)
        }
    }

    fun cancel() {
        try {
            alarmManager?.cancel(pendingIntent())
        } catch (e: Exception) {
            Log.w(TAG, "取消闹钟失败（记录照清，避免界面拿着一个已过期的时间点）", e)
        }
        prefs.edit().putLong(KEY_NEXT_AT, 0L).putLong(KEY_CADENCE, 0L).apply()
    }

    private fun pendingIntent(): PendingIntent {
        val intent = Intent(ACTION_ROUND_DUE).apply { setPackage(context.packageName) }
        return PendingIntent.getBroadcast(
            context,
            REQUEST_CODE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun flutterPrefs() =
        context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    /** 精确闹钟开关（设置页写入 `flutter.exact_alarm_enabled`）—— 与延迟推送同一份读法。 */
    private fun exactAllowed(): Boolean {
        return try {
            flutterPrefs().getBoolean("flutter.exact_alarm_enabled", false)
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Dart 侧那份收货总开关（`FnthinkSettings.keyReceiveEnabled`，落盘带 `flutter.` 前缀）。
     *
     * ⚠ 读不到必须按**关**处理：这个开关的语义是"这台设备从没同意过通知内容经服务器中转"，
     * 兜底成 true 就等于用户没同意过的东西在开机后自己醒。
     * ⚠ 键名是两端各写一份的字符串 —— Dart 那边改名，这里永远读到 false，表现是"闹钟从此
     * 不在开机后重排"，而全场测试仍然绿。那对关系由 `test/architecture/fnthink_presence_guard_test.dart` 钉。
     */
    private fun receiveEnabled(): Boolean = try {
        flutterPrefs().getBoolean("flutter.fnthink.receive_enabled", false)
    } catch (e: Exception) {
        false
    }

    /**
     * 重启（或系统把进程收走又放回来）之后，把那颗闹钟补回去（§4-9 片1c）。
     *
     * AlarmManager 的排程**不跨重启**：关机再开，链条上没有任何一处会自己补 —— 而 Dart 那一侧
     * 只有用户打开 App（引擎跑起来）才可能重排，那正是这一片要消掉的那段空窗。
     *
     * 这里**不自己算间隔**：用的还是 Dart 上次交下来并持久化的那一档（[cadenceSeconds]）。
     * 两个"不补"各有一条理由，都不是保险丝：
     *  - `cadence == 0` ⇒ 从来没人交过节奏（这台没开启过接收，或上一次被取消过），无事可做；
     *  - **开关关着 ⇒ 连那份 cadence 一起清掉**。留着它，下次开机又会重排一颗为"用户已经
     *    关掉的功能"服务的闹钟；而协调者那一发 `_presence` 在通道不通时是会失败的（它不重试），
     *    所以这份 prefs 完全可能比用户的开关旧 —— 开关才是真值。
     */
    fun armIfWantedAfterBoot() {
        val cadence = cadenceSeconds()
        if (cadence <= 0L) {
            Log.d(TAG, "开机不重排幻念收货闹钟：没有 Dart 交下来的节奏（这台没开启过接收，或已取消）")
            return
        }
        if (!receiveEnabled()) {
            Log.d(TAG, "开机不重排幻念收货闹钟：总开关是关着的，顺手清掉那份过期的节奏")
            cancel()
            return
        }
        Log.d(TAG, "开机重排幻念收货闹钟，沿用 Dart 上次交下来的那一档 cadence=$cadence")
        schedule(cadence)
    }
}
