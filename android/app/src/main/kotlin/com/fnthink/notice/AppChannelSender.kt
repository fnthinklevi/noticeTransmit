package com.fnthink.notice

import android.content.Context
import android.os.Build
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

/**
 * 自建应用通道发送器（应用通道体系）。
 *
 * 与 WebhookSender（webhook 体系）并列，负责把通知经「凭据换 token → 消息端点」
 * 的两阶段模型推送到各自建应用。管理完善度与 webhook 通道对齐：
 * - 送达结果经 DeliveryNotifier 回传（历史记录逐条徽标）
 * - 失败进入自动重试队列（RetryQueue 按 appChannelId 重放，重取新 token）
 * - 推送暂停开关生效（NetworkClient 层门控）
 * - 送达日志写入 webhook_delivery_log（Flutter updateDelivery 统一落库）
 */
class AppChannelSender(private val context: Context) {

    companion object {
        private const val TAG = "AppChannelSender"
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** token 获取专用客户端（与推送重试客户端隔离） */
    private val tokenClient: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(10, TimeUnit.SECONDS)
            .build()
    }

    fun destroy() {
        Log.d(TAG, "AppChannelSender destroyed")
    }

    /** 与 WebhookSender 对齐：@Volatile copy-on-write 配置注入 */
    @Volatile
    private var channelConfigs: List<AppChannelConfig> = emptyList()

    fun updateConfigs(configs: List<AppChannelConfig>) {
        channelConfigs = configs.filter { it.enabled }
        Log.d(TAG, "App channels updated: ${channelConfigs.size} channels")
    }

    /** 推送一条通知到全部启用的自建应用通道（通知到达 / 电量提醒主链路） */
    fun sendNotification(info: NotificationInfo) {
        for (cfg in channelConfigs) {
            sendSafely(cfg, info, force = false)
        }
    }

    /** 指定 force 的发送（延迟补推 / 手动现在推送 / 合并 flush） */
    fun sendOnly(
        info: NotificationInfo,
        force: Boolean = false,
        configs: List<AppChannelConfig>? = null,
    ) {
        for (cfg in configs ?: channelConfigs) {
            sendSafely(cfg, info, force = force)
        }
    }

    /**
     * 单通道发送隔离：任一通道的意外异常不得影响其他通道，更不得冒泡导致
     * Service/进程崩溃（多通道场景下「一个通道有问题 = 全部通道失效」不可接受）。
     */
    private fun sendSafely(cfg: AppChannelConfig, info: NotificationInfo, force: Boolean) {
        try {
            sendToSingle(cfg, info, force = force) { result ->
                // 可用性记账（T12）；此前这里恒传 null = 结果就地丢弃
                ChannelAvailability.noteResult(
                    context, "app", cfg.id,
                    success = result.status == WebhookResponseParser.DeliveryStatus.SUCCESS,
                )
            }
        } catch (e: Exception) {
            Log.e(TAG, "应用通道发送异常 type=${cfg.type} id=${cfg.id}", e)
        }
    }

    private fun sendToSingle(
        cfg: AppChannelConfig,
        info: NotificationInfo,
        force: Boolean,
        onResultDone: ((WebhookResponseParser.ParseResult) -> Unit)?,
    ) {
        val spec = AppChannelRegistry.spec(cfg.type)
        if (spec == null) {
            Log.e(TAG, "Unknown app channel type: ${cfg.type}")
            val fail = WebhookResponseParser.ParseResult(
                WebhookResponseParser.DeliveryStatus.BIZ_FAIL, 0, "未知应用通道类型", false
            )
            // 与其他失败分支一致：回传终态，避免记录停留在「发送中」且无痕迹
            notifyDeliveryResult(info.id, cfg.type, fail, cfg.baseUrl)
            onResultDone?.invoke(fail)
            return
        }
        val base = try {
            AppChannelTokenHelper.normalizeBase(cfg.baseUrl, spec.officialBase)
        } catch (e: IllegalArgumentException) {
            val fail = WebhookResponseParser.ParseResult(
                WebhookResponseParser.DeliveryStatus.BIZ_FAIL, 0, e.message ?: "地址无效", false
            )
            notifyDeliveryResult(info.id, cfg.type, fail, cfg.baseUrl)
            onResultDone?.invoke(fail)
            return
        }

        val content = spec.truncate(
            WebhookPayloadBuilder.buildTextBody(
                title = info.title,
                content = info.content,
                appName = info.appName,
                time = info.time,
                deviceName = PrefsHelper.deviceName.ifEmpty { android.os.Build.MODEL },
                notifyType = info.type,
            )
        )
        val markdown = cfg.messageFormat == "markdown" && spec.type == AppChannelTypes.WECOM_APP
        val payload = try {
            spec.buildPayload(cfg, content, markdown)
        } catch (e: IllegalArgumentException) {
            val fail = WebhookResponseParser.ParseResult(
                WebhookResponseParser.DeliveryStatus.BIZ_FAIL, 0, e.message ?: "载荷构造失败", false
            )
            notifyDeliveryResult(info.id, cfg.type, fail, cfg.baseUrl)
            onResultDone?.invoke(fail)
            return
        }
        val credential = credentialOf(cfg)

        fun deliver(attempt: Int) {
            val token = try {
                runBlocking {
                    AppChannelTokenManager.getToken(
                        cfg.type, credential,
                        SpecTokenFetcher(spec, cfg, base, tokenClient),
                    )
                }
            } catch (e: Exception) {
                // 兜底捕获所有异常（TokenFetchException / JSONException / 网络异常等）：
                // 任一异常都统一回传终态失败，避免冒泡导致进程崩溃或通道静默失效
                val msg = (e as? AppChannelTokenManager.TokenFetchException)?.message
                    ?: e.message ?: "获取 token 失败"
                val fail = WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.BIZ_FAIL, 0, msg, false
                )
                notifyDeliveryResult(info.id, cfg.type, fail, cfg.baseUrl)
                onResultDone?.invoke(fail)
                return
            }
            val (url, headers) = spec.sendTarget(cfg, base, token)
            NetworkClient.sendWithRetry(
                url = url,
                payload = payload,
                tag = "notification",
                webhookType = WebhookPayloadBuilder.WebhookType.GENERIC,
                secret = null,
                recordId = info.id,
                force = force,
                appChannelId = cfg.id,
                appTypeLabel = cfg.type,
                onResult = { result ->
                    Log.d(TAG, "Delivery(app:${cfg.type}) ${NetworkClient.sanitizeUrlHost(cfg.baseUrl)} → status=${result.status} msg=${result.message}")
                    if (attempt == 0 &&
                        result.status == WebhookResponseParser.DeliveryStatus.BIZ_FAIL &&
                        AppChannelTokenManager.isTokenErrorMessage(result.message)
                    ) {
                        Log.w(TAG, "App channel token expired, refresh and retry once")
                        AppChannelTokenManager.invalidate(AppChannelTokenManager.cacheKey(cfg.type, credential))
                        deliver(1)
                        return@sendWithRetry
                    }
                    notifyDeliveryResult(info.id, cfg.type, result, cfg.baseUrl)
                    onResultDone?.invoke(result)
                }
            )
        }
        deliver(0)
    }

    /**
     * 失败重试队列重放入口（RetryQueue 对 app 通道的重放走此方法）：
     * 用重放时新鲜的 token 重新发送队列中保存的载荷。
     */
    fun replayStored(item: RetryItem) {
        val cfg = ConfigManager(context).findAppChannelById(item.appChannelId)
        if (cfg == null) {
            Log.w(TAG, "重放跳过：应用通道已删除 id=${item.appChannelId}")
            RetryQueue.removeSuccess(context, item.id)
            return
        }
        val spec = AppChannelRegistry.spec(cfg.type)
        if (spec == null) {
            RetryQueue.removeSuccess(context, item.id)
            return
        }
        val base = try {
            AppChannelTokenHelper.normalizeBase(cfg.baseUrl, spec.officialBase)
        } catch (_: IllegalArgumentException) {
            RetryQueue.removeSuccess(context, item.id)
            return
        }
        val credential = credentialOf(cfg)
        val token = try {
            runBlocking {
                AppChannelTokenManager.getToken(
                    cfg.type, credential,
                    SpecTokenFetcher(spec, cfg, base, tokenClient),
                )
            }
        } catch (e: Exception) {
            Log.w(TAG, "重放获取 token 失败: ${e.message}")
            return
        }
        val (url, headers) = spec.sendTarget(cfg, base, token)
        NetworkClient.sendWithRetry(
            url = url,
            payload = item.payload,
            tag = "notification_retry",
            webhookType = WebhookPayloadBuilder.WebhookType.GENERIC,
            secret = null,
            contentType = item.contentType,
            force = true,
            extraHeaders = headers,
            onResult = { result ->
                if (result.status == WebhookResponseParser.DeliveryStatus.SUCCESS) {
                    RetryQueue.removeSuccess(context, item.id)
                    DeliveryNotifier.notify(
                        context, item.recordId, item.appType,
                        WebhookResponseParser.ParseResult(
                            WebhookResponseParser.DeliveryStatus.SUCCESS,
                            result.httpCode, result.message, false
                        ),
                        item.url
                    )
                    Log.i(TAG, "应用通道重放成功 record=${item.recordId}")
                }
            }
        )
    }

    /** 凭据摘要源：wecom=corpid+corpsecret；feishu=app_id+app_secret */
    private fun credentialOf(cfg: AppChannelConfig): String =
        cfg.config.optString("corpid", cfg.config.optString("app_id", "")) +
            "+" + cfg.secret

    private fun notifyDeliveryResult(
        notificationId: String,
        type: String,
        result: WebhookResponseParser.ParseResult,
        channelUrl: String,
    ) {
        DeliveryNotifier.notify(context, notificationId, type, result, channelUrl)
    }
}

/** Spec 的 token 获取实现适配（OkHttp 实例由持有方注入） */
private class SpecTokenFetcher(
    private val spec: AppChannelSpec,
    private val cfg: AppChannelConfig,
    private val base: String,
    private val client: OkHttpClient,
) : AppChannelTokenManager.TokenFetcher {
    override suspend fun fetch(): Pair<String, Int> = spec.fetchToken(cfg, base, client)
}
