package com.fnthink.notice

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.util.concurrent.atomic.AtomicBoolean

/**
 * 重试条目（纯数据）。
 *
 * [url]/[payload]/[secret]/[contentType]/[webhookType] 为失败时刻的完整重放参数——
 * 重放时**重新签名**（WebhookSigner.sign），不落盘签名结果（签名含时间戳，过期无意义）。
 * [recordId] 为推送历史记录 id：重放成功后经 DeliveryNotifier 回传，把记录从
 * 「推送失败」如实翻转为「推送成功」。
 */
data class RetryItem(
    val id: String,
    val url: String,
    val payload: String,
    val webhookType: String,
    val secret: String,
    val contentType: String,
    val recordId: String,
    val attempts: Int,
    val nextAttemptAt: Long,
    val createdAt: Long,
)

/**
 * 重试队列纯逻辑（无 Android 依赖，JVM 可测）。
 *
 * 约束（roadmap N4）：上限 50 条（保留最新）/ 过期 24h / 每条最多重放 3 次 /
 * 重放冷却 15 分钟（失败后不立即重打，避免与 NetworkClient 协程内重试叠加成风暴）。
 */
object RetryQueueLogic {
    const val MAX_RECORDS = 50
    const val MAX_AGE_MS = 24 * 60 * 60 * 1000L
    const val MAX_ATTEMPTS = 3
    const val COOLDOWN_MS = 15 * 60 * 1000L

    /** 是否可重放：未超限流冷却、未超重放次数、未过期（恰好 24h 仍可重放，超过才过期） */
    fun isReplayable(item: RetryItem, now: Long): Boolean {
        if (item.attempts >= MAX_ATTEMPTS) return false
        if (now - item.createdAt > MAX_AGE_MS) return false
        return now >= item.nextAttemptAt
    }

    /** 清扫：丢弃已超重放次数 / 已超过 24h 的条目（其历史记录保持「推送失败」如实状态） */
    fun purge(items: List<RetryItem>, now: Long): List<RetryItem> =
        items.filter { item ->
            item.attempts < MAX_ATTEMPTS && now - item.createdAt <= MAX_AGE_MS
        }

    /** 上限保护：超出 [MAX_RECORDS] 时保留最新（按 createdAt 降序取前 N） */
    fun applyCap(items: List<RetryItem>): List<RetryItem> {
        if (items.size <= MAX_RECORDS) return items
        return items.sortedByDescending { it.createdAt }.take(MAX_RECORDS)
    }

    /** 重放失败后的下次可重放时间：固定冷却 15 分钟 */
    fun nextAttemptAfter(now: Long): Long = now + COOLDOWN_MS

    fun toJson(items: List<RetryItem>): String {
        val arr = JSONArray()
        for (item in items) {
            arr.put(
                JSONObject().apply {
                    put("id", item.id)
                    put("url", item.url)
                    put("payload", item.payload)
                    put("webhookType", item.webhookType)
                    put("secret", item.secret)
                    put("contentType", item.contentType)
                    put("recordId", item.recordId)
                    put("attempts", item.attempts)
                    put("nextAttemptAt", item.nextAttemptAt)
                    put("createdAt", item.createdAt)
                }
            )
        }
        return arr.toString()
    }

    fun parse(json: String): List<RetryItem> {
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                RetryItem(
                    id = o.optString("id", ""),
                    url = o.optString("url", ""),
                    payload = o.optString("payload", ""),
                    webhookType = o.optString("webhookType", "GENERIC"),
                    secret = o.optString("secret", ""),
                    contentType = o.optString("contentType", "application/json; charset=utf-8"),
                    recordId = o.optString("recordId", ""),
                    attempts = o.optInt("attempts", 0),
                    nextAttemptAt = o.optLong("nextAttemptAt", 0L),
                    createdAt = o.optLong("createdAt", 0L),
                )
            }
        } catch (e: Exception) {
            emptyList()
        }
    }
}

/**
 * 失败推送自动重试队列（N4）。
 *
 * **背景**：`NetworkClient.sendWithRetry` 的重试发生在协程内，进程被杀即丢失；
 * 兜底是失败已写入推送历史（可手动「现在推送」），缺的是**自动重放**。
 *
 * **入队**：`NetworkClient` 在 webhook（tag == "notification"）重试耗尽且失败状态为
 * 可重试类（HTTP_FAIL / NETWORK_FAIL / RATE_LIMITED；BIZ_FAIL 属业务性拒绝不重试）
 * 且非 force（手动补推不再自动排队）时调用 [enqueue]。
 *
 * **存储**：SecurePrefs（加密文件）——payload 含通知内容，明文落盘违背项目加密原则。
 *
 * **重放触发**：① 服务启动（onCreate）；② 网络恢复（registerDefaultNetworkCallback）。
 * 重放前检查推送暂停开关（暂停 → 保持队列不动，与「用户主动暂停」语义一致）。
 *
 * **重放方式**：按条重发（`NetworkClient.sendWithRetry`，tag = "notification_retry"，
 * force = true——暂停门控已在 drain 时判定），成功 → 移出队列 + 回传记录送达状态
 * （failed → success 如实翻转）；失败 → attempts++ 并按冷却重排，超限/过期自动清扫。
 */
object RetryQueue {
    private const val TAG = "RetryQueue"
    private const val SECURE_KEY = "webhook_retry_queue"

    @Volatile
    private var appContext: Context? = null
    private val watching = AtomicBoolean(false)
    private val lock = Any()

    /** 幂等初始化（NetworkClient 无 Context，入队依赖此处注入的应用上下文） */
    fun init(context: Context) {
        if (appContext == null) {
            appContext = context.applicationContext
        }
    }

    private fun prefs(context: Context) = SecurePrefs.get(context)

    /** 入队（NetworkClient 重试耗尽时调用）：去重按 url+recordId，上限 50 保留最新 */
    fun enqueue(
        url: String,
        payload: String,
        webhookType: WebhookPayloadBuilder.WebhookType,
        secret: String?,
        contentType: String,
        recordId: String,
    ) {
        val context = appContext ?: run {
            Log.w(TAG, "enqueue skipped: queue not initialized")
            return
        }
        if (url.isEmpty() || payload.isEmpty()) return
        val now = System.currentTimeMillis()
        val item = RetryItem(
            id = "retry_${now}_${(url.hashCode().toLong() and 0xFFFFL)}",
            url = url,
            payload = payload,
            webhookType = webhookType.name,
            secret = secret ?: "",
            contentType = contentType,
            recordId = recordId,
            attempts = 0,
            nextAttemptAt = RetryQueueLogic.nextAttemptAfter(now),
            createdAt = now,
        )
        synchronized(lock) {
            val prefs = prefs(context)
            val items = RetryQueueLogic.parse(
                prefs.getString(SECURE_KEY, "[]") ?: "[]"
            ).filterNot { it.url == url && it.recordId == recordId } + item
            val capped = RetryQueueLogic.applyCap(items)
            prefs.edit().putString(SECURE_KEY, RetryQueueLogic.toJson(capped)).apply()
        }
        Log.i(TAG, "重试入队: ${NetworkClient.sanitizeUrlHost(url)} record=$recordId")
    }

    /**
     * 启动重放监视：服务 onCreate 调用。幂等（进程内仅注册一次网络回调）。
     * 触发时机：① 服务启动立即试一轮；② 网络恢复（onAvailable）再试一轮。
     */
    fun startWatching(context: Context) {
        init(context)
        replayIfEligible()
        if (!watching.compareAndSet(false, true)) return
        val cm = appContext?.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
        if (cm == null) {
            Log.w(TAG, "ConnectivityManager 不可用，仅启动时重放")
            return
        }
        try {
            cm.registerDefaultNetworkCallback(object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) {
                    Log.i(TAG, "网络恢复，重放失败队列")
                    replayIfEligible()
                }
            })
            Log.i(TAG, "重试队列网络监视已注册")
        } catch (e: Exception) {
            Log.e(TAG, "注册网络回调失败（仅保留启动重放）", e)
        }
    }

    /** 重放所有可重放条目：推送暂停时保持队列不动（与「用户主动暂停」语义一致） */
    fun replayIfEligible() {
        val context = appContext ?: return
        if (!PushToggleManager.isPushActive()) {
            Log.d(TAG, "推送暂停中，重试队列保持不动")
            return
        }
        val now = System.currentTimeMillis()
        val (replayable, rest) = synchronized(lock) {
            val prefs = prefs(context)
            val items = RetryQueueLogic.parse(
                prefs.getString(SECURE_KEY, "[]") ?: "[]"
            )
            val cleaned = RetryQueueLogic.purge(items, now)
            if (cleaned.size != items.size) {
                prefs.edit().putString(SECURE_KEY, RetryQueueLogic.toJson(cleaned)).apply()
            }
            val due = cleaned.filter { RetryQueueLogic.isReplayable(it, now) }
            if (due.isNotEmpty()) {
                // 立即记为「本轮已取出」（attempts++ + 冷却重排），防止网络回调风暴下重复重放
                val bumped = cleaned.map { item ->
                    if (RetryQueueLogic.isReplayable(item, now)) {
                        item.copy(attempts = item.attempts + 1, nextAttemptAt = RetryQueueLogic.nextAttemptAfter(now))
                    } else {
                        item
                    }
                }
                prefs.edit().putString(SECURE_KEY, RetryQueueLogic.toJson(bumped)).apply()
            }
            due to cleaned
        }
        if (replayable.isEmpty()) return
        Log.i(TAG, "重放失败队列：${replayable.size} 条")
        for (item in replayable) {
            sendOne(context, item)
        }
    }

    /** 单条重放：成功 → 移出队列 + 回传记录状态；失败 → 保留（attempts 已在取出时递增） */
    private fun sendOne(context: Context, item: RetryItem) {
        val type = try {
            WebhookPayloadBuilder.WebhookType.valueOf(item.webhookType)
        } catch (_: Exception) {
            WebhookPayloadBuilder.WebhookType.GENERIC
        }
        NetworkClient.sendWithRetry(
            url = item.url,
            payload = item.payload,
            tag = "notification_retry",
            webhookType = type,
            secret = item.secret.ifEmpty { null },
            contentType = item.contentType,
            force = true,
            recordId = item.recordId,
            onResult = { result ->
                if (result.status == WebhookResponseParser.DeliveryStatus.SUCCESS) {
                    synchronized(lock) {
                        val prefs = prefs(context)
                        val items = RetryQueueLogic.parse(
                            prefs.getString(SECURE_KEY, "[]") ?: "[]"
                        ).filterNot { it.id == item.id }
                        prefs.edit().putString(SECURE_KEY, RetryQueueLogic.toJson(items)).apply()
                    }
                    // 重放成功：记录从「推送失败」如实翻转为「推送成功」
                    DeliveryNotifier.notify(
                        context,
                        item.recordId,
                        item.webhookType,
                        WebhookResponseParser.ParseResult(
                            WebhookResponseParser.DeliveryStatus.SUCCESS,
                            result.httpCode,
                            result.message,
                            false
                        ),
                        item.url
                    )
                    Log.i(TAG, "重放成功: ${NetworkClient.sanitizeUrlHost(item.url)} record=${item.recordId}")
                } else {
                    Log.w(
                        TAG,
                        "重放仍失败（attempts=${item.attempts}）: " +
                            "${NetworkClient.sanitizeUrlHost(item.url)} → ${result.status} ${result.message}"
                    )
                }
            }
        )
    }
}
