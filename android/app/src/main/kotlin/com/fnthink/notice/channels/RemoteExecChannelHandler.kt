package com.fnthink.notice.channels

import com.fnthink.notice.FnthinkRemoteExecDisplay
import com.fnthink.notice.I18n
import com.fnthink.notice.MainActivity
import com.fnthink.notice.RemoteExecutionCancelStore
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 远程执行的原生那一格（片3c-5）：状态栏通知的显示/清理 + 那一格「被原生记下撤销」的读口。
 *
 * ⚠ **只有这三个方法**。执行链本身在 Dart 那边（`RemoteCommandRunner`），这里不碰状态机 ——
 *   一个"到点动手前问一句原生"之外的东西都不该落在这侧，
 *   否则同一个状态就有两个读者，而它们对不齐的时候没有任何症状。
 */
internal class RemoteExecChannelHandler(activity: MainActivity) : ChannelHandler(activity) {

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "fnthinkRemoteExecShow" -> {
                val execId = call.argument<String>("execId").orEmpty()
                val item = call.argument<String>("item").orEmpty()
                val seconds = call.argument<Int>("seconds") ?: 0
                if (execId.isEmpty()) {
                    // 通知的 id 与 exec_id 是同一个（它要能被 clear 按名字收掉），
                    // 空的那个发出去就是一条撤不掉的常驻 —— 不如不发。
                    result.success(false)
                    return true
                }
                result.success(
                    FnthinkRemoteExecDisplay.show(
                        activity,
                        FnthinkRemoteExecDisplay.Spec(
                            execId = execId,
                            title = activity.getString(
                                com.fnthink.notice.R.string.fnthink_remote_exec_title
                            ),
                            text = activity.getString(
                                com.fnthink.notice.R.string.fnthink_remote_exec_text,
                                item,
                                seconds,
                            ),
                            cancelLabel = I18n.remoteExecCancelLabel(),
                        ),
                    ),
                )
            }

            "fnthinkRemoteExecClear" -> {
                val execId = call.argument<String>("execId").orEmpty()
                if (execId.isNotEmpty()) FnthinkRemoteExecDisplay.clear(activity, execId)
                result.success(true)
            }

            // ⚠ `consume` 而不是 `peek`：问一次就清掉。留着会让"问一下"变成"看一眼"，
            //   而下一轮收货重投同一条指令时它会被读成"这次也撤了"，
            //   于是重投的那一次静默不执行 —— 而界面上一个字都看不出来。
            "fnthinkRemoteExecTakeCancelled" -> {
                val execId = call.argument<String>("execId").orEmpty()
                result.success(RemoteExecutionCancelStore.consume(activity, execId))
            }

            "fnthinkRemoteExecForget" -> {
                val execId = call.argument<String>("execId").orEmpty()
                RemoteExecutionCancelStore.forget(activity, execId)
                result.success(true)
            }

            else -> return false
        }
        return true
    }
}
