package com.fnthink.notice.channels

import android.content.Context
import com.fnthink.notice.AppLaunch
import com.fnthink.notice.CallLogSearch
import com.fnthink.notice.CameraSnap
import com.fnthink.notice.FnthinkAlertDisplay
import com.fnthink.notice.FnthinkIdentityStore
import com.fnthink.notice.FnthinkInboxDisplay
import com.fnthink.notice.FnthinkOpenTarget
import com.fnthink.notice.FnthinkPairLink
import com.fnthink.notice.FnthinkPresenceAlarm
import com.fnthink.notice.LocationFix
import com.fnthink.notice.SmsSearch
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
                    // T55 ③ 角标那个数。**数法只有 Dart 一处**（`countFnthinkInboxUnread`）：
                    // 原生这边不去查库也不自己数 —— 数法抄第二份迟早与首页那张卡对不上，
                    // 而"角标 3、首页写 5"是用户会当场看见的那种不一致。
                    // 缺这个键（老 Dart 或通道被直调）按 0 算，不报错：角标不是这条通知的身份。
                    unreadCount = call.argument<Int>("unreadCount") ?: 0,
                )
                result.success(FnthinkInboxDisplay.show(context, spec))
            }
            // ── T124 片B：让这台响一条（`alert:ring`）──
            // 与收件显示同一条渠道与同一条"没显示就回 false"的纪律：
            // 回 false 的那一次执行会被记成失败（对面收到 done 会以为用户被提醒过了）。
            "showFnthinkAlert" -> result.success(FnthinkAlertDisplay.show(context))
            // ── T124 片B：打开本机登记过的一条入口（`app:launch`）──
            // 目标是 Dart 侧校验过的串（`pkg/cls` 或一条带 scheme 的 URI）；
            // 原生这一层只负责"把它交给系统"，打开不了就回 false（与显示那几发同一条纪律）。
            "launchFnthinkTarget" -> {
                val target = call.argument<String>("target").orEmpty()
                result.success(
                    if (target.isBlank()) false else AppLaunch.launch(context, target),
                )
            }
            // ── T124 片B：按关键词搜本机短信（`sms:search`）──
            // 重活（库查询）下沉 ioScope（与配置那几发同一纪律）。
            // ⚠ 回 null = **没查成**（没给 READ_SMS / 被系统拒），回空表 = 查成了但没命中 ——
            //   两者在对面读起来完全不同（一个该去给权限，一个只是没命中）。
            "searchFnthinkSms" -> {
                val keyword = call.argument<String>("keyword").orEmpty().trim()
                ioScope.launch {
                    val rows =
                        if (keyword.isEmpty()) {
                            null
                        } else {
                            SmsSearch.search(context, keyword)
                        }
                    postSuccess(result, rows)
                }
            }
            // ── T124 片C：按关键词搜本机通话记录（`calls:search`）──
            // 与 sms 那一发逐字同形：重活下沉 ioScope，回 null = 没查成、回空表 = 查了没命中。
            // ⚠ 本机那枚开关（默认关）在 Dart 侧先判，过不来就压根到不了这里。
            "searchFnthinkCallLog" -> {
                val keyword = call.argument<String>("keyword").orEmpty().trim()
                ioScope.launch {
                    val rows =
                        if (keyword.isEmpty()) {
                            null
                        } else {
                            CallLogSearch.search(context, keyword)
                        }
                    postSuccess(result, rows)
                }
            }
            // ── T124 片C：读本机最近一次定位（`location:get`）──
            // 同上：回 null = 没查成（没权限/抛了），回空表 = 有权限但没有任何"最近一次"。
            "getFnthinkLocation" -> {
                ioScope.launch {
                    postSuccess(result, LocationFix.get(context))
                }
            }
            // ── T124 片C：让这台现在拍一张（`camera:snap`）──
            // 回 null = 没权限；回 {snap:false, why} = 没界面/拍失败（见 CameraSnap 文件头）；
            // 回 {snap:true, name, ...} = 成了 —— 三种下场在对面读起来不同。
            "snapFnthinkPhoto" -> {
                ioScope.launch {
                    postSuccess(result, CameraSnap.snap(context))
                }
            }
            // ── T83：点通知要跳去的那一条 ──
            // **冷启动那一发的唯一出口**：MainActivity 在 onCreate 里把 Intent 上的 messageId 记进
            // FnthinkOpenTarget，这里把它取走（取走即清）。为什么是 Dart 来拉而不是原生推：
            // configureFlutterEngine 早于 Dart 侧装 handler，那一刻推出去会静默丢，
            // 表现恰好是"点了通知只打开软件"——与这片要修的那个缺陷同形。
            // 空白从来没被记进去（见 FnthinkOpenTarget 的 ③），所以 null 的含义是唯一的：
            // 没有待跳的那条 ⇒ 页面只打开列表，不许猜一条。
            "takeFnthinkOpenTarget" -> result.success(FnthinkOpenTarget.take())
            // #176 片4：点开的那条配对链接。交的是**原始那一串**，判据全在 Dart 侧的契约读口里
            // （载荷名单 / 版本 / 口令形状 / 档位词表）—— 原生抄一份判据就是第二个作者。
            // 同样只给 take()：peek 是第二个读者，表现是同一个链接弹两次输入层。
            "takeFnthinkPairLink" -> result.success(FnthinkPairLink.take())
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
