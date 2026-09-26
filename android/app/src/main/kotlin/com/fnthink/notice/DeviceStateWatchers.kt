package com.fnthink.notice

import android.content.Context
import android.content.IntentFilter
import android.database.ContentObserver
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log

/**
 * 亮度与网络的**变化监听**（T24）。
 *
 * 为什么不是"要用时再读一次"：亮度与网络是**事件**。轮询要么几十秒才看见（用户早已把
 * 屏幕调亮了才收到"亮度低"的提醒），要么一直在打 syscall。而这两条链的判定入口只有一个：
 * 变化发生时叫 [BatteryMonitor.checkBatteryAndNotify] 再采一次 —— 与电量广播完全同构，
 * 不新造第二套"设备态触发"的形状。
 *
 * 值的读取一律走 [DeviceSnapshot] 那两处单一口径（`readBrightnessPercent` /
 * `readNetworkType`）：监听器只报"变了"，**不自己换算** —— 否则 ROM 值域那套换算
 * （0-255 / 0-100 / 自动亮度 -1）会出现第二份。
 *
 * ⚠ 生命周期：start/stop 成对且幂等，`onDestroy` 必须 stop。本仓库为"只注册不注销"
 * 付过学费（`RetryQueue` 那条同一批收口）—— 系统持有回调对象就等于持有整个 Service。
 */
class BrightnessWatcher(
    context: Context,
    private val onChange: () -> Unit,
) {
    private val appContext = context.applicationContext
    private var observer: ContentObserver? = null

    fun start() {
        if (observer != null) return
        val o = object : ContentObserver(Handler(Looper.getMainLooper())) {
            override fun onChange(selfChange: Boolean) {
                // 只往上抛"变了"：判定与推送交调用方（它会切 IO 协程），且亮度与亮度模式
                // 两个 URI 归到同一个入口 —— 任一变了都重采一次。
                onChange()
            }
        }
        try {
            appContext.contentResolver.registerContentObserver(
                Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS),
                false,
                o,
            )
            appContext.contentResolver.registerContentObserver(
                Settings.System.getUriFor(Settings.System.SCREEN_BRIGHTNESS_MODE),
                false,
                o,
            )
            observer = o
            Log.i(TAG, "亮度监听已注册")
        } catch (e: Exception) {
            Log.w(TAG, "亮度监听注册失败（亮度触发源本次不可用）: ${e.message}")
            observer = null
        }
    }

    fun stop() {
        observer?.let {
            try {
                appContext.contentResolver.unregisterContentObserver(it)
            } catch (e: Exception) {
                Log.w(TAG, "亮度监听注销失败: ${e.message}")
            }
        }
        observer = null
    }

    /** 注册成功与否都要能被界面/守卫读到：失败时触发源不可用，不能假装在监听。 */
    fun isWatching(): Boolean = observer != null
}

/**
 * 网络变化监听。回调里**重新读一次**当前网络而不是写死 "none"：多网络设备上掉的只是
 * 其中一条，另一条可能还活着 —— 直接报"无网络"就是假事实。
 */
class NetworkWatcher(
    context: Context,
    private val onChange: () -> Unit,
) {
    private val appContext = context.applicationContext
    private var cm: ConnectivityManager? = null
    private var callback: ConnectivityManager.NetworkCallback? = null

    fun start() {
        if (callback != null) return
        val manager = appContext.getSystemService(Context.CONNECTIVITY_SERVICE)
            as? ConnectivityManager
        if (manager == null) {
            Log.w(TAG, "ConnectivityManager 不可用，网络触发源本次不可用")
            return
        }
        cm = manager
        val cb = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) {
                onChange()
            }

            override fun onLost(network: Network) {
                onChange()
            }

            override fun onCapabilitiesChanged(
                network: Network,
                networkCapabilities: NetworkCapabilities,
            ) {
                onChange()
            }
        }
        // registerDefaultNetworkCallback 要 API 24+；拿不到就退回显式 NetworkRequest，
        // 语义不变（都是"变了就重采一次"）。
        val registered = runCatching { manager.registerDefaultNetworkCallback(cb) }
            .recoverCatching {
                Log.i(TAG, "默认网络回调不可用（${it.message}），退回 NetworkRequest 注册")
                manager.registerNetworkCallback(
                    NetworkRequest.Builder()
                        .addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
                        .build(),
                    cb,
                )
            }
        if (registered.isSuccess) {
            callback = cb
            Log.i(TAG, "网络监听已注册")
        } else {
            Log.w(TAG, "网络监听注册失败: ${registered.exceptionOrNull()?.message}")
            cm = null
        }
    }

    fun stop() {
        callback?.let {
            try {
                cm?.unregisterNetworkCallback(it)
            } catch (e: Exception) {
                Log.w(TAG, "网络监听注销失败: ${e.message}")
            }
        }
        callback = null
        cm = null
    }

    fun isWatching(): Boolean = callback != null
}

private const val TAG = "DeviceStateWatchers"
