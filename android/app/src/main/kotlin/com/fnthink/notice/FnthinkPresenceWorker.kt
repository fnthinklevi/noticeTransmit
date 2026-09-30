package com.fnthink.notice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.Worker
import androidx.work.WorkerParameters
import com.fnthink.notice.channels.ChannelDispatcher
import com.fnthink.notice.channels.FnthinkChannelHandler
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.embedding.engine.loader.FlutterLoader
import io.flutter.plugins.GeneratedPluginRegistrant
import io.flutter.view.FlutterCallbackInformation
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 被杀之后的那一轮收货：起一个后台 FlutterEngine，跑一轮，然后把它拆掉（T33 第二片 / §4-9）。
 *
 * 为什么必须是"引擎"而不是"服务"：poll 的签名私钥在 AndroidKeyStore、载荷加密与 nonce 全在
 * Dart 侧 —— **服务活着不等于 Dart isolate 活着**，光把进程拉起来一句话也签不出去。
 *
 * 两件本类必须自己做的事（都不是"照抄插件"）：
 *  1. **把幻念那条通道装到这台引擎上**。`MainActivity.configureFlutterEngine` 装的通道只属于
 *     UI 那台引擎；这里不装，Dart 一调 `signFnthinkBytes` 就是 `MissingPluginException`，
 *     而那种失败在后台**没人看得见**。（片0 `c139825` 就是为了这一步：那条 handler 以前要
 *     `MainActivity`，在这台引擎上根本构造不出来。）
 *  2. **跑不完必须留话并交出结果**。挂着不放，WorkManager 以为任务还在跑，后续那一轮永远排不上；
 *     悄悄 return 又不写日志，表现就是"闹钟明明开着却收不到"。
 *
 * 用 `Worker` + 一把 latch 而不是 `ListenableWorker` + `CallbackToFutureAdapter`：
 * 后者要 `androidx.concurrent:concurrent-futures`，而 work-runtime 把它声明成 `implementation`
 * （不外泄给 app 编译类路径）⇒ 为一把 future 再拉两条依赖不值得，而阻塞 worker 线程本来就是
 * `Worker` 的预期用法。引擎只能在主线程建/毁，所以那一步 post 回主线程，本线程只等。
 *
 * 超时/起不来一律 `Result.failure()` 而**不是** `retry()`：续下一轮是 [FnthinkPresenceReceiver]
 * 的活儿（用 Dart 交下来的 cadence），这里再排一次就是两套节奏互相追。
 */
class FnthinkPresenceWorker(appContext: Context, params: WorkerParameters) :
    Worker(appContext, params),
    io.flutter.plugin.common.MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private val finished = CountDownLatch(1)

    override fun doWork(): Result {
        val prefs =
            applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        // 入口 handle 由 Dart 在前台写（PluginUtilities.getCallbackHandle）。键名带 `flutter.`
        // 前缀是 shared_preferences 的存储形状，不是这里选的字符串。
        val handle = prefs.getLong(KEY_HANDLE, 0L)
        if (handle == 0L) {
            Log.e(TAG, "presence-round-skipped:no-entry-handle（App 还没在前台注册过后台入口）")
            return Result.success()
        }
        mainHandler.post { startEngine(handle) }
        val reported = finished.await(ROUND_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        destroyEngine()
        if (!reported) {
            Log.e(TAG, "presence-round-timeout（Dart 那一轮没在期限内交回结果）")
            return Result.failure()
        }
        return Result.success()
    }

    override fun onStopped() {
        // 系统要收走这个任务：立刻让引擎死掉并放开线程，别把 worker 挂在后台。
        finished.countDown()
        destroyEngine()
    }

    private fun startEngine(handle: Long) {
        try {
            val loader = FlutterLoader()
            if (!loader.initialized()) loader.startInitialization(applicationContext)
            loader.ensureInitializationCompleteAsync(applicationContext, null, mainHandler) {
                runEngine(loader, handle)
            }
        } catch (e: Exception) {
            Log.e(TAG, "presence-round-failed:flutter-init", e)
            finished.countDown()
        }
    }

    private fun runEngine(loader: FlutterLoader, handle: Long) {
        try {
            val info = FlutterCallbackInformation.lookupCallbackInformation(handle)
            val created = FlutterEngine(applicationContext)
            engine = created
            GeneratedPluginRegistrant.registerWith(created)
            // 幻念那条通道（身份与签名）与"这一轮跑完了"那条回报口，都挂在这台引擎上。
            io.flutter.plugin.common.MethodChannel(
                created.dartExecutor.binaryMessenger,
                APP_CHANNEL,
            ).setMethodCallHandler(DispatcherChannel())
            io.flutter.plugin.common.MethodChannel(
                created.dartExecutor.binaryMessenger,
                PRESENCE_CHANNEL,
            ).setMethodCallHandler(this)
            created.dartExecutor.executeDartCallback(
                DartExecutor.DartCallback(
                    applicationContext.assets,
                    loader.findAppBundlePath(),
                    info,
                ),
            )
        } catch (e: Exception) {
            Log.e(TAG, "presence-round-failed:engine-start", e)
            finished.countDown()
        }
    }

    /** Dart 侧唯一的回报口。别的调用一律 notImplemented —— 这里不代替前台做任何事。 */
    override fun onMethodCall(
        call: io.flutter.plugin.common.MethodCall,
        result: io.flutter.plugin.common.MethodChannel.Result,
    ) {
        if (call.method == "roundDone") {
            result.success(true)
            finished.countDown()
            return
        }
        result.notImplemented()
    }

    /** 把 App 自己的通道分发给这台引擎（MainActivity 那份分发器不在这儿，也不该在）。 */
    private inner class DispatcherChannel : io.flutter.plugin.common.MethodChannel.MethodCallHandler {
        private val dispatcher =
            ChannelDispatcher(listOf(FnthinkChannelHandler(applicationContext)))

        override fun onMethodCall(
            call: io.flutter.plugin.common.MethodCall,
            result: io.flutter.plugin.common.MethodChannel.Result,
        ) {
            if (!dispatcher.handle(call, result)) result.notImplemented()
        }
    }

    private fun destroyEngine() {
        val current = engine ?: return
        engine = null
        // 引擎只能在主线程销毁。已在主线程时直接执行，否则 post 回去再等它跑完 ——
        // 不"等"的代价是销毁还在跑而 worker 已退出：日志里会看到一次 engine is already attached to a thread。
        if (Looper.myLooper() == Looper.getMainLooper()) {
            runCatching { current.destroy() }
        } else {
            val done = CountDownLatch(1)
            mainHandler.post {
                runCatching { current.destroy() }
                done.countDown()
            }
            done.await(10, TimeUnit.SECONDS)
        }
    }

    private companion object {
        const val TAG = "FnthinkPresenceWorker"
        const val APP_CHANNEL = "com.fnthink.notice/notification"
        const val PRESENCE_CHANNEL = "com.fnthink.notice/presence"

        /** shared_preferences 写出来的键都带这个前缀（原生侧读时同样是这个形状）。 */
        const val KEY_HANDLE = "flutter.fnthink_presence_handle"

        /**
         * 一轮的期限：比 HTTP 超时（15s）长好几倍，因为这里还包含引擎启动、插件注册、
         * 一轮取货与落库；比 receiver 的生命周期长得多，正是它才需要 WorkManager 的理由。
         */
        const val ROUND_TIMEOUT_MS = 90_000L
    }
}
