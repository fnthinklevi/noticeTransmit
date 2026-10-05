package com.fnthink.notice

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.work.Constraints
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
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
 * 收到通知就转给幻念通道的那一发（T94 片4）。
 *
 * 为什么是"起引擎"而不是原生直接 HTTP：[FnthinkPresenceWorker] 已经把这件事测出来了 ——
 * 签名私钥在 AndroidKeyStore、载荷与 nonce 全在 Dart，**服务活着不等于 isolate 活着**。
 * 原生这一侧能判的只有"发哪儿"（`routeChannels()`），发的那一发必须回 Dart 去。
 *
 * 与收货那一轮（[FnthinkPresenceWorker]）的分工：**这一族是事件驱动的**（一条通知排一次），
 * 收货是节奏驱动的（每 N 秒一轮）。所以这里用 `OneTimeWorkRequest` + 唯一工作名
 * `enqueueUniqueWork(KEEP)`：一串通知连着到时只起**一次**引擎，一轮里把所有待发项排空 ——
 * 引擎起一次要几秒，起 N 次就是 N 倍的耗电，而用户只看到一个"转发了"。
 *
 * 三件本类必须自己做的事（与收货那一轮同因，不是"照抄"）：
 *  1. 把幻念那条通道装到这台引擎上（UI 那台引擎装的通道不属于这里）；
 *  2. 起引擎前确认**确实有待发项**（队列已被上一轮排空时这就是被合并掉的重复触发）；
 *  3. 跑不完必须留话并交出结果 —— 挂着不放，WorkManager 后续那一轮永远排不上。
 */
class FnthinkFanoutWorker(appContext: Context, params: WorkerParameters) :
    Worker(appContext, params),
    io.flutter.plugin.common.MethodChannel.MethodCallHandler {

    private val mainHandler = Handler(Looper.getMainLooper())
    private var engine: FlutterEngine? = null
    private val finished = CountDownLatch(1)

    override fun doWork(): Result {
        // 待发项**不**在这里取走：那份队列落在 FlutterSharedPreferences 就是为了让后台
        // isolate 用现成的 SharedPreferences 读到手，而"读 + 清"必须由同一侧连着做完
        // （本工程的 `DartExecutor.DartCallback` 只有三个构造参数，也没有入口参数位可交）。
        val pending = FnthinkFanoutQueue(applicationContext).pendingCount()
        if (pending == 0) {
            // 队列已被上一轮排空：这一次是被合并掉的重复触发，不是失败。
            Log.i(TAG, "fanout-round-skipped:empty-queue")
            return Result.success()
        }
        val prefs =
            applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        // 入口 handle 由 Dart 在前台写（PluginUtilities.getCallbackHandle）。键名带 `flutter.`
        // 前缀是 shared_preferences 的存储形状，不是这里选的字符串。
        val handle = prefs.getLong(KEY_HANDLE, 0L)
        if (handle == 0L) {
            // 这一条**故意不重排**：没交下入口就永远没有引擎可用，重试只是把同一批通知
            // 在队列里反复滚。取走即丢这件事由这条日志负责说出来。
            Log.e(TAG, "fanout-round-dropped:no-entry-handle（App 还没在前台注册过后台入口），$pending 条待发留在队列里")
            return Result.success()
        }
        mainHandler.post { startEngine(handle) }
        val reported = finished.await(ROUND_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        destroyEngine()
        if (!reported) {
            Log.e(TAG, "fanout-round-timeout（Dart 那一轮没在期限内交回结果，$pending 条待发已由它取走）")
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
            Log.e(TAG, "fanout-round-failed:flutter-init", e)
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
                FANOUT_CHANNEL,
            ).setMethodCallHandler(this)
            created.dartExecutor.executeDartCallback(
                DartExecutor.DartCallback(
                    applicationContext.assets,
                    loader.findAppBundlePath(),
                    info,
                ),
            )
        } catch (e: Exception) {
            Log.e(TAG, "fanout-round-failed:engine-start", e)
            finished.countDown()
        }
    }

    /** Dart 侧唯一的回报口。别的调用一律 notImplemented —— 这里不代替前台做任何事。 */
    override fun onMethodCall(
        call: io.flutter.plugin.common.MethodCall,
        result: io.flutter.plugin.common.MethodChannel.Result,
    ) {
        if (call.method == "fanoutDone") {
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

    companion object {
        const val TAG = "FnthinkFanoutWorker"
        const val APP_CHANNEL = "com.fnthink.notice/notification"
        const val FANOUT_CHANNEL = "com.fnthink.notice/fanout"

        /** shared_preferences 写出来的键都带这个前缀（原生侧读时同样是这个形状）。 */
        const val KEY_HANDLE = "flutter.fnthink_fanout_handle"

        /**
         * 唯一工作名。`enqueueUniqueWork(KEEP)` ⇒ 连着到时的多次触发只起一次引擎，
         * 一轮里排空全部待发项。改成别的名字（收货那一轮用的那个）会互相顶掉。
         */
        const val UNIQUE_WORK = "fnthink_fanout"

        /**
         * 排一轮（唯一入口：`NotificationMonitorService.dispatchToChannels`）。
         *
         * 背压交给 [FnthinkFanoutQueue] 的上限，不交给这里：`KEEP` 只保证"不重复起引擎"，
         * 队列一直满时真正该发生的是"丢最旧的"，而那个数字只有队列自己知道。
         */
        fun schedule(context: Context) {
            try {
                val request = OneTimeWorkRequestBuilder<FnthinkFanoutWorker>()
                    .setConstraints(Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build())
                    .build()
                WorkManager.getInstance(context)
                    .enqueueUniqueWork(UNIQUE_WORK, ExistingWorkPolicy.KEEP, request)
            } catch (e: Exception) {
                // 排不上就在这儿说一句：待发项已经落盘了，用户下一次收到通知时会再排一次。
                Log.e(TAG, "fanout-schedule-failed（待发项已落盘，下一条通知会再试）", e)
            }
        }

        /**
         * 一轮的期限：比 HTTP 超时（15s）长不少，因为这里还包含引擎启动、插件注册与逐条发送；
         * 比收货那一轮（90s）短 —— 队列最多 [FnthinkFanoutQueue.MAX_PENDING] 条，
         * 发不完的那一轮由日志说话，不值得让 WorkManager 一直等下去。
         */
        const val ROUND_TIMEOUT_MS = 120_000L
    }
}