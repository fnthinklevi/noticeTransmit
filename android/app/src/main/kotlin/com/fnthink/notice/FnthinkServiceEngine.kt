package com.fnthink.notice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.fnthink.notice.channels.ChannelDispatcher
import com.fnthink.notice.channels.ChannelMirrorInvalidationHandler
import com.fnthink.notice.channels.FnthinkChannelHandler
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.view.FlutterCallbackInformation

/**
 * 服务里的**常驻**幻念头（T197 片3）。
 *
 * 与 [FnthinkPresenceWorker] / [FnthinkFanoutWorker] 的分工：
 *  - 那两个是 WorkManager 起的**一轮引擎**，启动要等系统调度（实测通知到达后 5 秒才跑到，
 *    锁屏/Doze 下更久），而且是"起一次、跑完拆掉"；
 *  - 这一颗挂在 `NotificationMonitorService` 的进程里，**不退出**：收货循环由 Dart 侧
 *    按 UI 心跳决定要不要持有，待发队列则由原生直接 `fanoutNow` 叫它排空 ——
 *    不再每一条通知起一次引擎，也不再等 60 秒闹钟。
 *
 * 三条必须由本类守住：
 *  1. **只在服务活着时存在**：`ensure` 由 service 周期调用，`stop` 在 `onDestroy`；
 *  2. **僵尸自愈**：Dart 每 10 秒报一次 `alive`，90 秒没报就拆掉重建；
 *  3. **兜底不丢**：引擎没起来/调用失败 ⇒ 退回 `FnthinkFanoutWorker.schedule`，
 *     队列本身在 prefs 里，最坏也只是慢一轮。
 */
object FnthinkServiceEngine {
    private const val TAG = "FnthinkServiceEngine"

    /** 与 Dart `kFnthinkServiceChannel` 同名。 */
    const val SERVICE_CHANNEL = "com.fnthink.notice/service"

    /** 与 Dart `publishFnthinkServiceHandle` 的键同形（原生读带 `flutter.` 前缀的那份）。 */
    const val KEY_HANDLE = "flutter.fnthink_service_handle"

    /** Dart 报活超时：10 秒一次的心跳，给 9 次余量。 */
    private const val ALIVE_TIMEOUT_MS = 90_000L

    private val mainHandler = Handler(Looper.getMainLooper())

    @Volatile
    private var engine: FlutterEngine? = null

    @Volatile
    private var starting = false

    @Volatile
    private var lastAliveAt = 0L

    @Volatile
    private var fanoutBusy = false

    @Volatile
    private var fanoutAgain = false

    @Volatile
    private var appContext: Context? = null

    /** 服务侧周期调用：想要就建，不想要就收，僵尸就重建。 */
    fun ensure(context: Context, wanted: Boolean) {
        if (!wanted) {
            stop()
            return
        }
        appContext = context.applicationContext
        mainHandler.post {
            val current = engine
            if (current != null) {
                if (System.currentTimeMillis() - lastAliveAt <= ALIVE_TIMEOUT_MS) return@post
                Log.w(TAG, "service-engine-stale（Dart 超过 ${ALIVE_TIMEOUT_MS}ms 没报活），重建")
                destroyOnMain()
            }
            if (starting) return@post
            val handle = prefs()?.getLong(KEY_HANDLE, 0L) ?: 0L
            if (handle == 0L) {
                Log.i(TAG, "service-engine-waiting:no-entry-handle")
                return@post
            }
            starting = true
            startEngine(handle)
        }
    }

    /** 服务销毁时收掉引擎（不碰 WorkManager 的兜底）。 */
    fun stop() {
        mainHandler.post { destroyOnMain() }
    }

    /** 给 Worker 用：常驻引擎已经在跑收货时，那一轮 one-shot 可以直接跳过。 */
    fun isAlive(): Boolean {
        if (engine == null) return false
        return System.currentTimeMillis() - lastAliveAt <= ALIVE_TIMEOUT_MS
    }

    /**
     * 立即排空待发队列。返回 false = 常驻引擎不可用，调用方要退回 WorkManager。
     *
     * `fanoutBusy` 是去重闸：一轮还没回来时只记 `fanoutAgain`，不叠第二发；
     * 结果回来后再按"队列是否还有货"决定要不要接着排。
     */
    fun requestFanout(context: Context): Boolean {
        appContext = context.applicationContext
        val current = engine ?: return false
        if (fanoutBusy) {
            fanoutAgain = true
            return true
        }
        fanoutBusy = true
        try {
            MethodChannel(current.dartExecutor.binaryMessenger, SERVICE_CHANNEL).invokeMethod(
                "fanoutNow",
                null,
                object : MethodChannel.Result {
                    override fun success(result: Any?) {
                        fanoutBusy = false
                        val pending = FnthinkFanoutQueue(context.applicationContext).pendingCount()
                        if (fanoutAgain || pending > 0) {
                            fanoutAgain = false
                            if (pending > 0) requestFanout(context)
                        }
                    }

                    override fun error(code: String, message: String?, details: Any?) {
                        fanoutBusy = false
                        Log.w(TAG, "fanout-now-failed: $code $message（退回 WorkManager）")
                        fallback(context)
                    }

                    override fun notImplemented() {
                        fanoutBusy = false
                        Log.w(TAG, "fanout-now-not-implemented（退回 WorkManager）")
                        fallback(context)
                    }
                },
            )
            return true
        } catch (e: Exception) {
            fanoutBusy = false
            Log.w(TAG, "fanout-now-call-failed（退回 WorkManager）", e)
            fallback(context)
            return false
        }
    }

    private fun fallback(context: Context) {
        FnthinkFanoutWorker.schedule(context.applicationContext)
    }

    private fun prefs() =
        appContext?.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private fun startEngine(handle: Long) {
        val context = appContext
        if (context == null) {
            starting = false
            return
        }
        try {
            val loader = FlutterLoader()
            if (!loader.initialized()) loader.startInitialization(context)
            loader.ensureInitializationCompleteAsync(context, null, mainHandler) {
                runEngine(loader, handle)
            }
        } catch (e: Exception) {
            starting = false
            Log.e(TAG, "service-engine-failed:flutter-init", e)
        }
    }

    private fun runEngine(loader: FlutterLoader, handle: Long) {
        val context = appContext
        if (context == null) {
            starting = false
            return
        }
        try {
            val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
            val created = FlutterEngine(context)
            engine = created
            lastAliveAt = System.currentTimeMillis()
            GeneratedPluginRegistrant.registerWith(created)
            MethodChannel(created.dartExecutor.binaryMessenger, FnthinkFanoutWorker.APP_CHANNEL)
                .setMethodCallHandler(DispatcherChannel(context))
            MethodChannel(created.dartExecutor.binaryMessenger, SERVICE_CHANNEL)
                .setMethodCallHandler(
                    object : MethodChannel.MethodCallHandler {
                        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
                            if (call.method == "alive") {
                                lastAliveAt = System.currentTimeMillis()
                                result.success(true)
                            } else {
                                result.notImplemented()
                            }
                        }
                    },
                )
            created.dartExecutor.executeDartCallback(
                DartExecutor.DartCallback(context.assets, loader.findAppBundlePath(), info),
            )
            starting = false
            Log.i(TAG, "service-engine-started")
        } catch (e: Exception) {
            starting = false
            engine = null
            Log.e(TAG, "service-engine-failed:engine-start", e)
        }
    }

    private fun destroyOnMain() {
        val current = engine
        engine = null
        starting = false
        fanoutBusy = false
        fanoutAgain = false
        if (current != null) runCatching { current.destroy() }
    }

    private class DispatcherChannel(private val context: Context) : MethodChannel.MethodCallHandler {
        private val dispatcher =
            ChannelDispatcher(
                listOf(
                    FnthinkChannelHandler(context),
                    ChannelMirrorInvalidationHandler(context),
                ),
            )

        override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
            if (!dispatcher.handle(call, result)) result.notImplemented()
        }
    }
}

/** 发送端的唯一触发口：常驻引擎可用就立即排空，否则退回 WorkManager 那枚 one-shot。 */
object FnthinkFanoutNow {
    fun request(context: Context) {
        if (FnthinkServiceEngine.requestFanout(context)) return
        FnthinkFanoutWorker.schedule(context.applicationContext)
    }
}
