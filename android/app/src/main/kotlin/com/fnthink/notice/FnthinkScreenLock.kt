package com.fnthink.notice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.util.Log

/**
 * T197 片2：锁屏持续接收的服务侧持锁。
 *
 * 与 [FnthinkLiveMode] 分工：
 *  - [FnthinkLiveMode] 是 Dart 每轮续的"常驻轮询档"锁，SSE 健康时会被放掉；
 *  - 本对象是**服务自己**按屏幕状态持有的锁：接收开 + 高可靠开关开 + 屏幕灭 ⇒ 持锁；
 *    屏幕亮/接收关/开关关/服务销毁 ⇒ 放锁。它不依赖 Dart 每轮续，所以主 isolate
 *    睡着时这把锁仍在（这正是片2要补的那一段）。
 *
 * 续期：10 分钟超时、每 5 分钟重 acquire 一次。进程若被冻结，续期 Handler 不跑，
 * 锁最迟 10 分钟后自然过期 —— 宁可少耗电，也不留一把永不过期的锁。
 */
object FnthinkScreenLock {
    private const val TAG = "FnthinkScreenLock"
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val WAKE_TAG = "fnthink:screen-off"

    const val KEY_RECEIVE_ENABLED = "flutter.fnthink.receive_enabled"
    const val KEY_SCREEN_KEEPALIVE = "flutter.fnthink.screen_keepalive"

    internal const val WAKE_TIMEOUT_MS = 10 * 60 * 1000L
    internal const val RENEW_MS = 5 * 60 * 1000L

    private var wakeLock: PowerManager.WakeLock? = null
    private var handler: Handler? = null
    private var renew: Runnable? = null

    private fun prefs(context: Context) =
        context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)

    fun receiveEnabled(context: Context): Boolean = try {
        prefs(context).getBoolean(KEY_RECEIVE_ENABLED, false)
    } catch (e: Exception) {
        false
    }

    fun keepaliveEnabled(context: Context): Boolean = try {
        prefs(context).getBoolean(KEY_SCREEN_KEEPALIVE, true)
    } catch (e: Exception) {
        true
    }

    fun isHolding(): Boolean = wakeLock?.isHeld == true

    /** 服务启动时按"此刻屏幕是不是亮着"对一次账（服务可能在屏幕已灭时才被拉起）。 */
    fun refresh(context: Context) {
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        val screenOn = pm?.isInteractive ?: true
        apply(context, screenOn)
    }

    fun onScreenOff(context: Context) {
        apply(context, screenOn = false)
    }

    fun onScreenOn(context: Context) {
        apply(context, screenOn = true)
    }

    private fun apply(context: Context, screenOn: Boolean) {
        val wanted = FnthinkScreenLockPolicy.shouldHold(
            receiveEnabled = receiveEnabled(context),
            keepaliveEnabled = keepaliveEnabled(context),
            screenOn = screenOn,
        )
        if (wanted) acquire(context) else release()
    }

    private fun acquire(context: Context) {
        try {
            val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            if (pm == null) {
                Log.w(TAG, "没有 PowerManager，锁屏持锁跳过")
                return
            }
            val alreadyHeld = wakeLock?.isHeld == true
            val lock = wakeLock ?: pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_TAG)
                .apply { setReferenceCounted(false) }
                .also { wakeLock = it }
            // 重复 acquire 只续期（setReferenceCounted(false)），不会加引用计数。
            lock.acquire(WAKE_TIMEOUT_MS)
            if (!alreadyHeld) Log.d(TAG, "锁屏持续接收持锁")
            scheduleRenew(context)
        } catch (e: Exception) {
            Log.e(TAG, "锁屏持续接收持锁失败", e)
        }
    }

    private fun scheduleRenew(context: Context) {
        try {
            val h = handler ?: Handler(Looper.getMainLooper()).also { handler = it }
            renew?.let { h.removeCallbacks(it) }
            val runnable = Runnable {
                // 到点按**当前**屏幕/开关对账，不盲目续：用户可能已关掉开关或屏幕已亮。
                refresh(context)
            }
            renew = runnable
            h.postDelayed(runnable, RENEW_MS)
        } catch (e: Exception) {
            Log.w(TAG, "锁屏续期排程失败", e)
        }
    }

    fun release() {
        try {
            handler?.let { h -> renew?.let { h.removeCallbacks(it) } }
            renew = null
            wakeLock?.let {
                if (it.isHeld) it.release()
            }
        } catch (e: Exception) {
            Log.w(TAG, "锁屏放锁失败", e)
        } finally {
            wakeLock = null
        }
    }
}

/** 纯判据：接收开 + 高可靠开关开 + 屏幕灭。JVM 可测，不碰 PowerManager。 */
internal object FnthinkScreenLockPolicy {
    fun shouldHold(
        receiveEnabled: Boolean,
        keepaliveEnabled: Boolean,
        screenOn: Boolean,
    ): Boolean = receiveEnabled && keepaliveEnabled && !screenOn
}
