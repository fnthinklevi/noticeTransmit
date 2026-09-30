package com.fnthink.notice.channels

import android.content.Context
import com.fnthink.notice.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 单一 MethodChannel 按域分发的 Handler 契约。
 *
 * handle 返回 true 表示该调用已被本 Handler 消费；返回 false 时由
 * [ChannelDispatcher] 交给下一个 Handler，全部未消费则回 notImplemented
 * （与拆分前的 else 分支行为一致，Flutter 侧仍收到 MissingPluginException）。
 *
 * ⚠ 为什么分两层（`ChannelScope` 拿 Context、`ChannelHandler` 拿 Activity）：
 * 幻念推送那一族（身份、签名、把一条收件显示成通知）**只需要 Context**，
 * 而"只需要 Activity"是因为基类强制，不是因为业务需要。被 Activity 绑住的那一族
 * 在**后台引擎里根本装不出来**（没有 Activity 可传）—— 表现不是报错，是沉默：
 * 闹钟把任务排上了、engine 起来了、Dart 一调 `signFnthinkBytes` 就 `MissingPluginException`，
 * 而"被杀之后还要去问一次货"这一片要消灭的恰恰就是这种沉默的收不到（T33 第二片 / §4-9 的前置）。
 * 需要跳系统页、请求运行时权限、起前台服务的那一族继续走 [ChannelHandler]。
 */
internal abstract class ChannelScope(protected val context: Context) {
    abstract fun handle(call: MethodCall, result: MethodChannel.Result): Boolean

    /**
     * 域 Handler 通用 IO 作用域：`handle` 运行在**平台线程**（MethodChannel 回调），
     * 文件哈希 / SAF 写入 / prefs 全量 JSON 解析 / PackageManager 查询等重活必须
     * 下沉到这里，否则通知风暴或大包操作直接卡住 Flutter UI（表现为点一下卡数秒）。
     */
    protected val ioScope =
        kotlinx.coroutines.CoroutineScope(
            kotlinx.coroutines.SupervisorJob() + kotlinx.coroutines.Dispatchers.IO,
        )

    /** 切回主线程回传结果（MethodChannel.Result 必须在平台线程调用） */
    protected fun postSuccess(result: MethodChannel.Result, value: Any?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try {
                result.success(value)
            } catch (_: Exception) {
                // Activity 已销毁 / 已被回过一次：忽略
            }
        }
    }

    /** 重活异常不得冒泡到平台线程（会让 Flutter 侧收到未捕获异常）。 */
    protected fun postError(result: MethodChannel.Result, code: String, message: String) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try {
                result.error(code, message, null)
            } catch (_: Exception) {}
        }
    }
}

/** 只有需要 Activity 的那一族才继承这个（跳系统设置页、运行时权限、起服务）。 */
internal abstract class ChannelHandler(protected val activity: MainActivity) : ChannelScope(activity)

/**
 * 通道分发器：依序尝试各域 Handler，首个消费者胜出。
 * MainActivity.configureFlutterEngine 只负责装配，不再持有任何业务分支。
 *
 * 类型收在 [ChannelScope] 上：这样"需不需要 Activity"这件事由各个 Handler 自己说，
 * 而不是被分发器强制成同一个形状。
 */
internal class ChannelDispatcher(private val handlers: List<ChannelScope>) {
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean =
        handlers.firstOrNull { it.handle(call, result) } != null
}
