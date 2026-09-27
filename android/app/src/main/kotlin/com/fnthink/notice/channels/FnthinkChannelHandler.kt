package com.fnthink.notice.channels

import com.fnthink.notice.FnthinkIdentityStore
import com.fnthink.notice.MainActivity
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

/**
 * 幻念推送身份域（T26 B 半）：把设备身份公钥与"给一段规范化字节签名"暴露给 Flutter。
 *
 * ⚠ 这里**只出公钥与签名**：私钥既不进返回值，也不进日志与错误消息 —— 契约
 * `identity.identityKey.neverIn` 列的是 url/log/qrPayload/serverRequestBody，通道返回值
 * 属于同一类"会被顺手打出来看看"的地方，一并按不可导出处理。
 */
internal class FnthinkChannelHandler(activity: MainActivity) : ChannelHandler(activity) {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "getFnthinkIdentity" -> {
                ioScope.launch {
                    try {
                        val identity = FnthinkIdentityStore.identity(activity)
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
                            activity,
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
            else -> return false
        }
        return true
    }
}
