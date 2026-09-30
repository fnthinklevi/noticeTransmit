package com.fnthink.notice.channels

import android.content.Context
import com.fnthink.notice.FnthinkIdentityStore
import com.fnthink.notice.FnthinkInboxDisplay
import com.fnthink.notice.FnthinkPresenceAlarm
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

/**
 * 幻念推送域（T26 B 半 + T48 前置）：设备身份公钥、规范化字节签名，以及"把一条收件显示成通知"。
 *
 * 三件事放在同一个 handler 里是因为它们同属"只有幻念推送会用"的那一族，而都只出**非敏感**的入参出参。
 *
 * ⚠ 这里**只出公钥与签名**：私钥既不进返回值，也不进日志与错误消息 —— 契约
 * `identity.identityKey.neverIn` 列的是 url/log/qrPayload/serverRequestBody，通道返回值
 * 属于同一类"会被顺手打出来看看"的地方，一并按不可导出处理。
 */
internal class FnthinkChannelHandler(context: Context) : ChannelScope(context) {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "getFnthinkIdentity" -> {
                ioScope.launch {
                    try {
                        val identity = FnthinkIdentityStore.identity(context)
                        postSuccess(
                            result,
                            mapOf(
                                "publicKey" to identity.publicKeyBase64,
                                "plan" to identity.plan.contractValue,
                                "keystoreBacked" to identity.keystoreBacked,
                            ),
                        )
                    } catch (e: Exception) {
                        postError(result, "identity_unavailable", e.message ?: "身份密钥不可用")
                    }
                }
            }
            "signFnthinkBytes" -> {
                val canonical = call.argument<String>("canonicalBase64")
                if (canonical.isNullOrBlank()) {
                    result.error("bad_argument", "canonicalBase64 不能为空", null)
                    return true
                }
                ioScope.launch {
                    try {
                        val signature = FnthinkIdentityStore.sign(
                            context,
                            android.util.Base64.decode(canonical, android.util.Base64.NO_WRAP),
                        )
                        postSuccess(
                            result,
                            android.util.Base64.encodeToString(signature, android.util.Base64.NO_WRAP),
                        )
                    } catch (e: Exception) {
                        postError(result, "sign_failed", e.message ?: "签名失败")
                    }
                }
            }
            "showFnthinkInbox" -> {
                val messageId = call.argument<String>("messageId").orEmpty()
                if (messageId.isBlank()) {
                    // 没有 id 就没有可撤回/可标记的东西，直接回"没显示"而不是报错：
                    // 调用方（收货循环）只需要一个布尔来决定 ack 的取值。
                    result.success(false)
                    return true
                }
                val spec = FnthinkInboxDisplay.specFor(
                    messageId = messageId,
                    sender = call.argument<String>("sender").orEmpty(),
                    title = call.argument<String>("title").orEmpty(),
                    body = call.argument<String>("body").orEmpty(),
                )
                result.success(FnthinkInboxDisplay.show(context, spec))
            }
            // ── "到点去问一次货"的闹钟（T33 第二片 / §4-9）──
            // 节奏的唯一读者是 Dart（契约 `presence.pollIntervalSeconds` / `burstWhenPending`）：
            // 这里**不自己算间隔**，只负责"把这个数交给系统"与"取消"。
            // 三个方法都是同步的（AlarmManager / prefs.apply 都是内存级），不必下沉到 ioScope。
            "scheduleFnthinkPresence" -> {
                val seconds = call.argument<Number>("seconds")?.toLong()
                    ?: call.argument<String>("seconds")?.toLongOrNull()
                    ?: 0L
                FnthinkPresenceAlarm(context).schedule(seconds)
                result.success(true)
            }
            "cancelFnthinkPresence" -> {
                FnthinkPresenceAlarm(context).cancel()
                result.success(true)
            }
            "fnthinkPresenceStatus" -> {
                // 界面/日志要能问出"到底还有没有人醒"：只有排上了 / 没排上两个状态是不够的，
                // 还得说得出下一轮在什么时候、那一档间隔是多少（后者是 Dart 上次交下来的那一份）。
                val alarm = FnthinkPresenceAlarm(context)
                result.success(
                    mapOf(
                        "nextRoundAt" to alarm.nextRoundAt(),
                        "cadenceSeconds" to alarm.cadenceSeconds(),
                    ),
                )
            }
            else -> return false
        }
        return true
    }
}
