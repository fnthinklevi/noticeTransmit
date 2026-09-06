package com.fnthink.notice.channels

import com.fnthink.notice.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 单一 MethodChannel 按域分发的 Handler 契约。
 *
 * handle 返回 true 表示该调用已被本 Handler 消费；返回 false 时由
 * [ChannelDispatcher] 交给下一个 Handler，全部未消费则回 notImplemented
 * （与拆分前的 else 分支行为一致，Flutter 侧仍收到 MissingPluginException）。
 */
internal abstract class ChannelHandler(protected val activity: MainActivity) {
    abstract fun handle(call: MethodCall, result: MethodChannel.Result): Boolean
}

/**
 * 通道分发器：依序尝试各域 Handler，首个消费者胜出。
 * MainActivity.configureFlutterEngine 只负责装配，不再持有任何业务分支。
 */
internal class ChannelDispatcher(private val handlers: List<ChannelHandler>) {
    fun handle(call: MethodCall, result: MethodChannel.Result): Boolean =
        handlers.firstOrNull { it.handle(call, result) } != null
}
