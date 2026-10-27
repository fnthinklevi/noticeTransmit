package com.fnthink.notice.channels

import android.content.Context
import android.content.Intent
import com.fnthink.notice.ChannelMirrorInvalidator
import com.fnthink.notice.NotificationMonitorService
import com.fnthink.notice.PrefsHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.launch

internal class ChannelMirrorInvalidationHandler(context: Context) : ChannelScope(context) {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "invalidateChannelMirrors" -> {
                val phase = call.argument<String>("phase")
                if (phase == "begin") {
                    ioScope.launch {
                        val ok = runCatching { ChannelMirrorInvalidator.begin(context) }
                            .getOrDefault(false)
                        postSuccess(result, ok)
                    }
                } else if (phase == "finish") {
                    ioScope.launch {
                        val ok = runCatching { ChannelMirrorInvalidator.invalidate(context) }
                            .getOrDefault(false)
                        if (!ok) {
                            postError(
                                result,
                                "channel-mirror-invalidation-failed",
                                "Channel mirrors remain blocked; retry invalidation",
                            )
                            return@launch
                        }
                        PrefsHelper.webhookUrls = emptyList()
                        NotificationMonitorService.webhookUrls = emptyList()
                        runCatching {
                            context.startService(
                                Intent(context, NotificationMonitorService::class.java).apply {
                                    action = NotificationMonitorService.ACTION_UPDATE_CONFIG
                                },
                            )
                        }
                        postSuccess(result, true)
                    }
                } else {
                    result.error("channel-mirror-invalidation-phase", "Unknown phase", null)
                }
                return true
            }
            else -> return false
        }
    }
}
