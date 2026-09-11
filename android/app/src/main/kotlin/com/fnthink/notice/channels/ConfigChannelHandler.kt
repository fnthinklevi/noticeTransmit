package com.fnthink.notice.channels

import com.fnthink.notice.DiagLog
import com.fnthink.notice.EmailManager
import com.fnthink.notice.I18n
import com.fnthink.notice.MainActivity
import com.fnthink.notice.NotificationMonitorService
import com.fnthink.notice.PrefsHelper
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * 配置域：locale 与桌面别名、崩溃上报开关、Webhook/邮件通道配置与测试、
 * 电池规则/设置、短信监听设置、通知规则、应用过滤与黑白名单关键词、监听服务启停。
 */
internal class ConfigChannelHandler(activity: MainActivity) : ChannelHandler(activity) {
    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "setLocaleLabel" -> {
                val locale = call.arguments as? String ?: "zh"
                activity.prefs.edit().putString("flutter.locale", locale).apply()
                // 同步给 Webhook 推送国际化模块
                I18n.setLocale(locale)
                activity.switchLocaleAlias()
                activity.updateAppLabel()
                result.success(true)
            }
            "initCrashReport" -> {
                // 用户在设置页开启崩溃上报后调用；幂等，未同意时为 no-op
                activity.maybeInitCrashReport()
                result.success(activity.crashReportInitialized)
            }
            "setWebhookUrls" -> {
                val urls = call.argument<List<String>>("urls") ?: emptyList()
                val validUrls = urls.filter { it.isNotEmpty() }
                PrefsHelper.webhookUrls = validUrls
                activity.saveWebhookUrls(validUrls)
                NotificationMonitorService.webhookUrls = validUrls
                activity.notifyServiceConfigChanged()
                result.success(true)
            }
            "getWebhookChannels" -> {
                result.success(activity.getWebhookChannels())
            }
            "setWebhookChannels" -> {
                val channels = call.argument<List<Map<String, Any?>>>("channels") ?: emptyList()
                activity.setWebhookChannels(channels)
                result.success(true)
            }
            "getEmailChannels" -> {
                result.success(EmailManager.loadChannelsAsMap(activity))
            }
            "setEmailChannels" -> {
                val channels = call.argument<List<Map<String, Any?>>>("channels") ?: emptyList()
                EmailManager.saveChannels(activity, channels)
                result.success(true)
            }
            "testEmail" -> {
                val configMap = call.arguments as? Map<String, Any?> ?: emptyMap()
                activity.testEmail(configMap, result)
            }
            "testWebhook" -> {
                val url = call.argument<String>("url") ?: ""
                val secret = call.argument<String>("secret")
                activity.testWebhook(url, secret, result)
            }
            "setBatteryRules" -> {
                val rules = call.argument<List<Map<String, Any>>>("rules") ?: emptyList()
                activity.setBatteryRules(rules)
                result.success(true)
            }
            "setBatterySetting" -> {
                val key = call.argument<String>("key") ?: ""
                val value = call.argument<Boolean>("value") ?: false
                activity.setBatterySetting(key, value)
                result.success(true)
            }
            "setSmsSetting" -> {
                // 短信监听配置（总开关/监听卡/验证码开关）。短信与电话链路每次
                // 事件都新建 ConfigManager 实时读取，无需 notifyServiceConfigChanged
                val key = call.argument<String>("key") ?: ""
                val value = call.argument<Any?>("value")
                activity.setSmsSetting(key, value)
                result.success(true)
            }
            "setNotificationRules" -> {
                // 保存通知规则（优先级分级 / 延迟推送等由原生 RuleEngine 执行），并通知服务热更新配置
                val rules = call.argument<List<Map<String, Any?>>>("rules") ?: emptyList()
                activity.setNotificationRules(rules)
                result.success(true)
            }
            "toggleDiagLog" -> {
                // N7 诊断模式产品化：翻转开发者诊断日志（DiagLog），返回切换后的状态，
                // 持久化于原生 prefs（App/Service 启动时 init 恢复）
                result.success(DiagLog.toggle(activity))
            }
            "setEnabledPackages" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                activity.setEnabledPackages(packages)
                result.success(true)
            }
            "getEnabledPackages" -> {
                result.success(activity.getEnabledPackages())
            }
            "setAppFilter" -> {
                val packages = call.argument<List<String>>("packages") ?: emptyList()
                val mode = call.argument<String>("mode") ?: "allow"
                activity.setAppFilter(packages, mode)
                result.success(true)
            }
            "getAppFilterMode" -> {
                result.success(activity.getAppFilterMode())
            }
            "setBlacklistKeywords" -> {
                val keywords = call.argument<List<String>>("keywords") ?: emptyList()
                activity.setBlacklistKeywords(keywords)
                result.success(true)
            }
            "getBlacklistKeywords" -> {
                result.success(activity.getBlacklistKeywords())
            }
            "setWhitelistKeywords" -> {
                val keywords = call.argument<List<String>>("keywords") ?: emptyList()
                activity.setWhitelistKeywords(keywords)
                result.success(true)
            }
            "getWhitelistKeywords" -> {
                result.success(activity.getWhitelistKeywords())
            }
            "startNotificationListener" -> {
                activity.startNotificationListener()
                result.success(true)
            }
            "stopNotificationListener" -> {
                activity.stopNotificationListener()
                result.success(true)
            }
            else -> return false
        }
        return true
    }
}
