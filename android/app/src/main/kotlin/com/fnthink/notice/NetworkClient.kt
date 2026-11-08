package com.fnthink.notice

import android.content.Context
import android.os.PowerManager
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.withPermit
import okhttp3.CertificatePinner
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit

class NetworkClient {
    companion object {
        private const val TAG = "NetworkClient"
        private const val MAX_RETRIES = 3
        private const val RETRY_DELAY_MS = 2000L
        private const val RATE_LIMIT_RETRY_DELAY_MS = 10_000L // 限流时退避更长

        /** T244：单次发送生命周期（含 3 次重试与退避）的 wake lock 硬上限。 */
        internal const val SEND_WAKE_LOCK_MS = 60_000L

        /**
         * 隐私脱敏：webhook URL 含平台 secret（Telegram bot token / Bark key /
         * ServerChan SendKey 在路径中，企业微信 key / PushPlus token 在 query 中）。
         * 日志只允许记录 host；禁止完整 URL 或固定长度截断（截断可能暴露路径型 token）。
         */
        fun sanitizeUrlHost(url: String): String =
            try {
                java.net.URI(url).host ?: "unknown-host"
            } catch (_: Exception) {
                "invalid-url"
            }

        /**
         * 送达判定使用的平台身份：**调用方显式声明的类型优先，仅当其为 GENERIC 时**才按 host 回退。
         *
         * 旧实现在 [sendOnce] 里无条件 `detectType(signed.url)`，把调用方传进来的 `webhookType`
         * 直接丢掉。后果：GOTIFY 与自建 ntfy 在 `ChannelRegistry` 里刻意不登记 host（域名由用户
         * 自填），于是它们永远被判成 GENERIC，平台业务码判定形同虚设（假成功 / 假失败都可能）。
         *
         * 保留 GENERIC→host 回退是必须的：应用通道（企微/飞书自建应用）复用本管线时传 GENERIC
         * （它们不属于 WebhookType 体系），端点就是平台官方域名，靠 host 才拿得到真实判定。
         */
        fun resolveWebhookType(
            explicit: WebhookPayloadBuilder.WebhookType,
            url: String
        ): WebhookPayloadBuilder.WebhookType =
            if (explicit != WebhookPayloadBuilder.WebhookType.GENERIC) explicit
            else WebhookPayloadBuilder.detectType(url)

        @Volatile private var isActive = true
        // T244/T245：发送路径的电源态读数需要 Context（ wake lock / isDeviceIdleMode）。
        // 无 Context 时两处都降级为不持锁 / 不附注——发送照常，只是少一层韧性少一行取证。
        @Volatile private var appContext: Context? = null
        // 作用域在 destroy() 时 cancel，activate() 时重建，避免重试协程在服务销毁后仍回调
        private var scope = newScope()
        private fun newScope() = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        /**
         * 幂等注入应用上下文（NotificationMonitorService.onCreate 调用）。
         * T244 wake lock 与 T245 电源态取证位共用这一份。
         */
        fun init(context: Context) {
            if (appContext == null) {
                appContext = context.applicationContext
            }
        }

        /**
         * 全局发送并发上限（背压）。
         *
         * 群刷屏场景下一条通知起 N 个发送协程 + 3 次重试会形成请求风暴：
         * 企业微信机器人硬限 20 条/分钟（超限 45009）、Telegram 同 token 30 条/秒。
         * 上限 3 使第 4+ 条在协程层排队（而非压向平台），配合指数退避削峰。
         */
        private val sendLimiter = kotlinx.coroutines.sync.Semaphore(3)

        private val client: OkHttpClient by lazy {
            OkHttpClient.Builder()
                .connectTimeout(15, TimeUnit.SECONDS)
                .writeTimeout(15, TimeUnit.SECONDS)
                .readTimeout(15, TimeUnit.SECONDS)
                .retryOnConnectionFailure(false)
                .apply {
                    // SSL 证书固定：防止中间人攻击。默认关闭（CERT_PINS 为空或
                    // ENABLE_CERT_PINNING=false，Debug 构建恒关闭）。
                    // 启用方式：构建时注入环境变量/参数
                    //   CERT_PINS="sha256/xxx;sha256/yyy" ENABLE_CERT_PINNING=true
                    // 获取指纹：
                    //   openssl s_client -connect notice.fnthink.top:443 -servername notice.fnthink.top 2>/dev/null \
                    //     | openssl x509 -pubkey -noout | openssl pkey -pubin -outform der | openssl dgst -sha256 -binary \
                    //     | openssl base64
                    // 证书轮换与多 pin 策略见 base.md「证书固定」章节。
                    buildCertificatePinner()?.let { certificatePinner(it) }
                }
                .build()
        }

        /**
         * 构建证书固定器。多 pin 用「;」分隔（至少保留 2 个：当前 + 备用），
         * 未启用（Debug / 未注入 / 空指纹）时返回 null，仅做标准 TLS 验证。
         */
        private fun buildCertificatePinner(): CertificatePinner? {
            if (!BuildConfig.ENABLE_CERT_PINNING) return null
            val pins = BuildConfig.CERT_PINS
                .split(';')
                .map { it.trim() }
                .filter { it.isNotEmpty() && it.startsWith("sha256/") }
            if (pins.isEmpty()) return null
            val hosts = listOf("notice.fnthink.top", "xget.fnthink.top")
            return CertificatePinner.Builder().apply {
                for (host in hosts) {
                    for (pin in pins) {
                        add(host, pin)
                    }
                }
            }.build()
        }

        /**
         * 发送 webhook（支持签名 + 送达校验）
         *
         * @param url 原始 webhook URL
         * @param payload JSON payload
         * @param tag 日志标签
         * @param webhookType 平台类型（用于响应解析）
         * @param secret 签名密钥（null/empty 时不签名）
         * @param contentType 请求体 MIME 类型（默认 application/json; charset=utf-8）。
         *                    当使用自定义模板（text/xml/markdown）时由调用方传入对应类型。
         * @param force 强制发送：为 true 时忽略"推送暂停"开关（用于历史记录"现在推送"手动补推）
         * @param onResult 可选回调，返回送达结果（含状态/HTTP 码/消息）
         * @param recordId 推送历史记录 id（N4：webhook 推送重试耗尽且失败可重试时，
         *                 携带它入自动重试队列，重放成功后可回传翻转记录状态；
         *                 tag != "notification" 或无需入队时传 null）
         */
        fun sendWithRetry(
            url: String,
            payload: String,
            tag: String = "webhook",
            webhookType: WebhookPayloadBuilder.WebhookType = WebhookPayloadBuilder.WebhookType.GENERIC,
            secret: String? = null,
            contentType: String = "application/json; charset=utf-8",
            force: Boolean = false,
            recordId: String? = null,
            extraHeaders: Map<String, String> = emptyMap(),
            appChannelId: String? = null,
            appTypeLabel: String? = null,
            // T188 片1：请求方法。缺省 POST ⇒ 七个调用点里没传的一律保持既有行为。
            // ⚠ 值必须已经过 `ChannelDispatch.plan` 按描述符过滤；这里不再判合法性（判了就是第二处裁决）。
            method: String = HttpMethods.DEFAULT,
            onResult: ((WebhookResponseParser.ParseResult) -> Unit)? = null
        ) {
            if (!isActive) {
                onResult?.invoke(
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.NETWORK_FAIL,
                        0, "NetworkClient inactive", false
                    )
                )
                return
            }
            // 推送已暂停（前台通知一键启停）：监听继续，仅跳过 webhook 发送。
            // 手动"现在推送"（force=true）不受暂停开关限制。
            if (!force && !PushToggleManager.isPushActive()) {
                Log.d(TAG, "$tag skipped: push paused")
                onResult?.invoke(
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.PAUSED,
                        0, "Push paused (skipped)", false
                    )
                )
                return
            }
            scope.launch {
                sendLimiter.withPermit {
                    // T251：内联重试次数读通道描述符的重试预算（数据驱动，不按类型分支）。
                    // Server酱/PushPlus 这类「失败也计数」的平台预算为 1。
                    val inlineRetries = ChannelRegistry.spec(
                        resolveWebhookType(webhookType, url)
                    ).retryBudget.inlineRetries
                    // T244：发送生命周期持 partial wake lock（Doze 下被系统忽略无害；
                    // 豁免用户的灭屏/轻度 idle 段生效——没有它 CPU 可能在 TLS 握手/写入
                    // 中途睡眠，把 15s 超时拖成 3 连败）。60s 硬上限 = 3×15s 超时 + 退避
                    // 的最坏覆盖，finally 恒释放。
                    val wakeLock = acquireSendWakeLock()
                    try {
                        // 发送前签名（仅一次，重试时复用同一签名）
                        val signed = WebhookSigner.sign(webhookType, url, payload, secret)

                        var retryCount = 0
                        var lastResult: WebhookResponseParser.ParseResult? = null
                        // T220：取证从"真的开始发"算起 —— 排队等信号量的那段不算这一发的耗时。
                        val startedAtMs = System.currentTimeMillis()

                        while (retryCount < inlineRetries) {
                            val result = sendOnce(signed, tag, retryCount, contentType, extraHeaders, webhookType, method)
                            lastResult = result

                            // 成功或不可重试 → 终止
                            if (result.status == WebhookResponseParser.DeliveryStatus.SUCCESS) {
                                Log.d(TAG, "$tag delivered (attempt ${retryCount + 1}): ${result.message}")
                                onResult?.invoke(result.withTelemetry(startedAtMs, retryCount + 1))
                                return@withPermit
                            }
                            if (!result.retryable) {
                                Log.e(TAG, "$tag delivery failed (no retry): ${result.message}")
                                onResult?.invoke(result.withTelemetry(startedAtMs, retryCount + 1))
                                return@withPermit
                            }

                            Log.w(TAG, "$tag delivery failed (attempt ${retryCount + 1}), will retry: ${result.message}")
                            retryCount++

                            if (retryCount < MAX_RETRIES) {
                                // 指数退避（2s, 4s, ...）；平台限流（如企业微信 45009）用更长基数。
                                // T248：对端官方给出 Retry-After 时遵循之——夹紧到 [1,60] 秒：
                                // 低于下限容易再撞限流；高于 60 秒的（如 Server酱 24h 封禁）不.inline
                                // 干等，靠既有队列冷却节奏消化（结果仍可重试，耗尽后自然入队）。
                                val backoff = 1L shl (retryCount - 1)
                                val delayMs = when (result.status) {
                                    WebhookResponseParser.DeliveryStatus.RATE_LIMITED -> {
                                        val official = result.retryAfterSeconds
                                        if (official != null && official > 0) {
                                            official.coerceIn(1, 60) * 1000L
                                        } else {
                                            RATE_LIMIT_RETRY_DELAY_MS * backoff
                                        }
                                    }
                                    else -> RETRY_DELAY_MS * backoff
                                }
                                delay(delayMs)
                            }
                        }

                        // 重试耗尽
                        Log.e(TAG, "$tag delivery exhausted retries: ${lastResult?.message}")
                        // N4 自动重试队列：仅 webhook 推送（tag == "notification"）且失败状态
                        // 属可重试类（HTTP_FAIL / NETWORK_FAIL / RATE_LIMITED）时入队。
                        // 手动「现在推送」（force = true）失败不再自动排队；
                        // BIZ_FAIL 为业务性拒绝（重试无意义）；PAUSED 在入口已短路不会到此；
                        // tag = sms / phone / notification_retry 的链路各自处理，不入本队列。
                        //
                        // T241：入队**成功**时把回传改判 QUEUED（非终态）——历史格显示「已转入
                        // 自动重试」而不是红色失败，重放成功后照 N4 既有链路翻绿；入队失败
                        // （未初始化/空参数）回传原失败结果，保持诚实。
                        var enqueued = false
                        if (tag == "notification" && !force && lastResult != null) {
                            when (lastResult.status) {
                                WebhookResponseParser.DeliveryStatus.HTTP_FAIL,
                                WebhookResponseParser.DeliveryStatus.NETWORK_FAIL,
                                WebhookResponseParser.DeliveryStatus.RATE_LIMITED -> enqueued = RetryQueue.enqueue(
                                    url = url,
                                    payload = payload,
                                    webhookType = webhookType,
                                    secret = secret,
                                    contentType = contentType,
                                    recordId = recordId ?: "",
                                    extraHeaders = extraHeaders,
                                    appChannelId = appChannelId,
                                    appTypeLabel = appTypeLabel,
                                    method = method,
                                )
                                else -> {}
                            }
                        }
                        // 重试耗尽终点（T241 后仍是一个打戳点，DeliveryTelemetrySourceGuardTest 锁着）：
                        // enqueued ⇒ QUEUED（已转自动重试）；否则原失败结果
                        val terminal = if (enqueued && lastResult != null) {
                            lastResult.copy(
                                status = WebhookResponseParser.DeliveryStatus.QUEUED,
                                message = "发送失败已转入自动重试队列，解锁/联网后自动补发 · ${lastResult.message}",
                            )
                        } else {
                            lastResult ?: WebhookResponseParser.ParseResult(
                                WebhookResponseParser.DeliveryStatus.NETWORK_FAIL,
                                0, "Unknown failure after $inlineRetries attempts", false
                            )
                        }
                        onResult?.invoke(terminal.withTelemetry(startedAtMs, retryCount))
                    } finally {
                        wakeLock?.let {
                            try {
                                if (it.isHeld) it.release()
                            } catch (_: Exception) {}
                        }
                    }
                }
            }
        }

        /** T244：拿发送期 wake lock；无 Context / 异常时返回 null（发送照常，只是不持锁）。 */
        private fun acquireSendWakeLock(): PowerManager.WakeLock? {
            val ctx = appContext ?: return null
            return try {
                val pm = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return null
                pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "fnthink:webhook-send")
                    .apply { acquire(SEND_WAKE_LOCK_MS) }
            } catch (_: Exception) {
                null
            }
        }

        /**
         * T220：给这一发打上「试了几次、花了多久」。只在真正发过请求的那条路上调用 ——
         * 上游那两个早退（未激活 / 推送暂停）一个请求都没发，attempts 保持 0（未知）。
         */
        private fun WebhookResponseParser.ParseResult.withTelemetry(
            startedAtMs: Long,
            attemptCount: Int
        ): WebhookResponseParser.ParseResult = copy(
            attempts = attemptCount,
            elapsedMs = (System.currentTimeMillis() - startedAtMs).coerceAtLeast(0L).toInt()
        )

        private fun sendOnce(
            signed: WebhookSigner.SignedRequest,
            tag: String,
            attempt: Int,
            contentType: String = "application/json; charset=utf-8",
            extraHeaders: Map<String, String> = emptyMap(),
            webhookType: WebhookPayloadBuilder.WebhookType = WebhookPayloadBuilder.WebhookType.GENERIC,
            method: String = HttpMethods.DEFAULT,
        ): WebhookResponseParser.ParseResult {
            return try {
                val requestBody =
                    if (HttpMethods.isBodyless(method)) {
                        // OkHttp 对 GET/HEAD 带 body 直接抛 IllegalArgumentException ⇒ 这一档必须真的不带。
                        // 正文仍然照常签名（`signed.payload` 是签出来的那份），只是不进请求 ——
                        // 用 GET 收通知的平台本来就只看 URL/头，扔掉 body 不改变签名口径。
                        null
                    } else {
                        signed.payload.toRequestBody(contentType.toMediaType())
                    }
                val requestBuilder = Request.Builder()
                    .url(signed.url)
                    .addHeader("User-Agent", "NotificationMonitor/1.0")
                    .method(method, requestBody)

                // 通用 webhook 签名头
                for ((k, v) in signed.headers) {
                    requestBuilder.addHeader(k, v)
                }
                // 应用通道鉴权头（如飞书 Bearer token，v1.5.73）
                for ((k, v) in extraHeaders) {
                    requestBuilder.addHeader(k, v)
                }

                val request = requestBuilder.build()

                client.newCall(request).execute().use { response ->
                    // okhttp 5 起 `Response.body` 是**非空**的（4.x 是 `ResponseBody?`）⇒
                    // 这里不再需要 `?.`（留着会吃一条 "unnecessary safe call" 警告）。
                    val respBody = response.body.string()
                    // T248：限流退避遵循对端官方语义——Slack/Discord 的 Retry-After 头
                    // （Telegram 的 parameters.retry_after 在体里，由解析器读）
                    val retryAfter = response.header("Retry-After")?.trim()?.toIntOrNull()
                    val parser = WebhookResponseParser.parse(
                        // 显式声明优先，GENERIC 才按 host 回退（见 resolveWebhookType 注释）
                        resolveWebhookType(webhookType, signed.url),
                        response.code,
                        respBody,
                        retryAfter,
                    )
                    Log.d(TAG, "$tag HTTP ${response.code} (attempt ${attempt + 1}): ${parser.message}")
                    parser
                }
            } catch (e: Exception) {
                Log.e(TAG, "$tag network error (attempt ${attempt + 1}): ${e.message}")
                WebhookResponseParser.ParseResult(
                    WebhookResponseParser.DeliveryStatus.NETWORK_FAIL,
                    // T245：失败消息附设备电源态取证位（[idle]/[light]/[no-exempt]）——
                    // 真机一条失败即可区分「Doze 挂起网络 / Flyme 叠加限制 / 普通网络抖动」，
                    // 不再靠猜。读不到 Context / PowerManager 时不附注。
                    0, "Network error: ${e.message}${powerStateSuffix()}", true
                )
            }
        }

        fun destroy() {
            isActive = false
            // 取消全部进行中的发送/重试协程，避免服务销毁后回调（最长约 34 秒退避）
            scope.cancel()
            Log.d(TAG, "NetworkClient deactivated (coroutines cancelled)")
        }

        fun activate() {
            isActive = true
            if (!scope.isActive) {
                scope = newScope()
            }
            Log.d(TAG, "NetworkClient activated")
        }

        /** T245：电源态取证位。JVM 判据在 [PowerStateTags]；这里只负责读数与降级。 */
        private fun powerStateSuffix(): String {
            val ctx = appContext ?: return ""
            val pm = ctx.getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return ""
            return try {
                PowerStateTags.suffix(
                    deviceIdle = pm.isDeviceIdleMode,
                    batteryExempt = pm.isIgnoringBatteryOptimizations(ctx.packageName),
                )
            } catch (_: Exception) {
                ""
            }
        }
    }
}

/**
 * T245 取证位的**纯判据**（JVM 可测）：把设备电源态折成短标签追加进失败消息。
 *
 * - `[idle]`：深睡（deep Doze）——官方语义：未豁免应用网络挂起；
 * - `[no-exempt]`：**未**豁免电池优化——Doze 限制全套生效。
 * 两个读数独立附注，可组合（`[idle][no-exempt]` = 深睡且未豁免，教科书 Doze 形态）。
 * ⚠ 轻度 Doze 的读数（isLightDeviceIdleMode）在本 SDK 桩上不可见，缺席——
 *   D4 拍板的门控也只判深 Doze，口径一致。
 */
internal object PowerStateTags {
    fun suffix(deviceIdle: Boolean, batteryExempt: Boolean): String {
        var s = ""
        if (deviceIdle) s += "[idle]"
        if (!batteryExempt) s += "[no-exempt]"
        return s
    }
}
