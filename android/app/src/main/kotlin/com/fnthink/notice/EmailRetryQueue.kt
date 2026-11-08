package com.fnthink.notice

import android.content.Context
import android.os.PowerManager
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * 邮件重试队列条目（纯数据）。
 *
 * [configId] 指回邮件通道配置（重放时**重读**配置取密码——用户在排队期间改了授权码，
 * 重放用的是改后的，防止用陈旧凭据反复撞认证）；[subject]/[body] 是失败那一刻**渲染好的**
 * 正文（重放不重排模板：设备态变量如 %battery% 在补发那一刻已经是陈旧的，照 T186 片1
 * 「不拿陈旧读数冒充此刻」的同一纪律）。
 */
data class EmailRetryItem(
    val id: String,
    val configId: String,
    val subject: String,
    val body: String,
    val recordId: String,
    val attempts: Int,
    val nextAttemptAt: Long,
    val createdAt: Long,
)

/**
 * 邮件重试队列纯逻辑（无 Android 依赖，JVM 可测）。
 *
 * 形状与 [RetryQueueLogic] 同源，数值按邮件场景放宽：
 * - 重放冷却 **30 分钟**（webhook 是 15 分钟）：一封信重放 = 再寄一封，冷却取宽防骚扰；
 * - 每条最多重放 **2 次**（webhook 3 次）：同上，一封信重放三遍的骚扰大于收益；
 * - 上限 20 / 过期 24h：与 webhook 队列同一档体量口径。
 */
object EmailRetryQueueLogic {
    const val MAX_RECORDS = 20
    const val MAX_AGE_MS = 24 * 60 * 60 * 1000L
    const val MAX_ATTEMPTS = 2
    const val COOLDOWN_MS = 30 * 60 * 1000L

    /** 是否可重放：未超重放次数、未过期、过了冷却 */
    fun isReplayable(item: EmailRetryItem, now: Long): Boolean =
        item.attempts < MAX_ATTEMPTS &&
            now - item.createdAt <= MAX_AGE_MS &&
            now >= item.nextAttemptAt

    /** 清扫：丢弃已超重放次数 / 已过期的条目（其历史记录保持「推送失败」如实状态） */
    fun purge(items: List<EmailRetryItem>, now: Long): List<EmailRetryItem> =
        items.filter { it.attempts < MAX_ATTEMPTS && now - it.createdAt <= MAX_AGE_MS }

    /** 上限保护：超出 [MAX_RECORDS] 时保留最新（按 createdAt 降序取前 N） */
    fun applyCap(items: List<EmailRetryItem>): List<EmailRetryItem> {
        if (items.size <= MAX_RECORDS) return items
        return items.sortedByDescending { it.createdAt }.take(MAX_RECORDS)
    }

    /** 重放失败后的下次可重放时间：固定冷却 30 分钟 */
    fun nextAttemptAfter(now: Long): Long = now + COOLDOWN_MS

    fun toJson(items: List<EmailRetryItem>): String {
        val arr = JSONArray()
        for (item in items) {
            arr.put(
                JSONObject().apply {
                    put("id", item.id)
                    put("configId", item.configId)
                    put("subject", item.subject)
                    put("body", item.body)
                    put("recordId", item.recordId)
                    put("attempts", item.attempts)
                    put("nextAttemptAt", item.nextAttemptAt)
                    put("createdAt", item.createdAt)
                }
            )
        }
        return arr.toString()
    }

    fun parse(json: String): List<EmailRetryItem> {
        return try {
            val arr = JSONArray(json)
            (0 until arr.length()).mapNotNull { i ->
                val o = arr.optJSONObject(i) ?: return@mapNotNull null
                EmailRetryItem(
                    id = o.optString("id", ""),
                    configId = o.optString("configId", ""),
                    subject = o.optString("subject", ""),
                    body = o.optString("body", ""),
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
 * T243：邮件失败的自动重放队列。
 *
 * 为什么独立成队列而不复用 webhook 的 RetryQueue：条目形状不同构（邮件是
 * configId+渲染正文，webhook 是 url+payload+recordId），硬套会污染 webhook 队列的
 * URL/recordId 语义（D2 拍板）。触发面与 RetryQueue **完全一致**（服务 onCreate /
 * 网络恢复 / T239 解锁亮屏），深睡门控同 T240 一份判据。
 *
 * **入队判据在调用方**（NotificationMonitorService.dispatchEmail）：只有瞬时失败
 * （超时/连接/DNS/SSL/421，[EmailSender.isTransientFailure]）才入队——配置类失败
 * （认证/550）重试无意义，且 QQ/163 对连续认证失败有临时封禁，重放那封信等于拿账号
 * 去撞封禁（T115 护栏②的同一教训）。
 *
 * **存储**：SecurePrefs（加密文件）——正文含通知内容，明文落盘违背项目加密原则
 * （与 RetryQueue 的 SecurePrefs 同一条纪律）。
 */
object EmailRetryQueue {
    private const val TAG = "EmailRetryQueue"
    private const val SECURE_KEY = "email_retry_queue"
    private val lock = Any()

    @Volatile
    private var appContext: Context? = null

    /** 幂等初始化（与 RetryQueue.init 同形） */
    fun init(context: Context) {
        if (appContext == null) {
            appContext = context.applicationContext
        }
    }

    private fun prefs(context: Context) = SecurePrefs.get(context)

    /** 入队：去重按 configId+recordId，上限 20 保留最新。返回 true = 已写盘。 */
    fun enqueue(
        configId: String,
        subject: String,
        body: String,
        recordId: String,
    ): Boolean {
        val context = appContext ?: run {
            Log.w(TAG, "enqueue skipped: queue not initialized")
            return false
        }
        if (configId.isEmpty() || subject.isEmpty() || body.isEmpty()) return false
        val now = System.currentTimeMillis()
        val item = EmailRetryItem(
            id = "email_retry_${now}_${(configId.hashCode().toLong() and 0xFFFFL)}",
            configId = configId,
            subject = subject,
            body = body,
            recordId = recordId,
            attempts = 0,
            nextAttemptAt = EmailRetryQueueLogic.nextAttemptAfter(now),
            createdAt = now,
        )
        synchronized(lock) {
            val prefs = prefs(context)
            val items = EmailRetryQueueLogic.parse(
                prefs.getString(SECURE_KEY, "[]") ?: "[]"
            ).filterNot { it.configId == configId && it.recordId == recordId } + item
            val capped = EmailRetryQueueLogic.applyCap(items)
            // 与 RetryQueue 同一条纪律：commit()（apply 在进程被杀时可能整笔丢失——
            // 丢「入队」= 失败邮件永不重放，丢「出队」= 同一封信重复寄）
            prefs.edit().putString(SECURE_KEY, EmailRetryQueueLogic.toJson(capped)).commit()
        }
        Log.i(TAG, "邮件重试入队: configId=$configId record=$recordId")
        RetryReplayAlarm.schedule(context)
        return true
    }

    /** T239：最早到期时间（供重放闹钟排程）。无待重放条目返回 0。 */
    fun earliestDueAt(now: Long): Long {
        val context = appContext ?: return 0L
        return synchronized(lock) {
            EmailRetryQueueLogic.parse(
                prefs(context).getString(SECURE_KEY, "[]") ?: "[]"
            )
                .filter {
                    it.attempts < EmailRetryQueueLogic.MAX_ATTEMPTS &&
                        now - it.createdAt <= EmailRetryQueueLogic.MAX_AGE_MS
                }
                .minOfOrNull { it.nextAttemptAt } ?: 0L
        }
    }

    /**
     * 重放所有可重放条目。门控与 [RetryQueue.replayIfEligible] 完全一致：
     * 镜像失效 / 推送暂停 / 深睡未豁免（T240 同一份判据）。
     */
    fun replayIfEligible() {
        val context = appContext ?: return
        if (ChannelMirrorInvalidator.isPending(context)) return
        if (!PushToggleManager.isPushActive()) {
            Log.d(TAG, "推送暂停中，邮件重试队列保持不动")
            return
        }
        val pm = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
        if (pm != null && RetryIdleGatePolicy.shouldDefer(
                deviceIdle = pm.isDeviceIdleMode,
                batteryExempt = pm.isIgnoringBatteryOptimizations(context.packageName),
            )
        ) {
            Log.i(TAG, "深睡中且未豁免电池优化，邮件重放延后（不烧次数）")
            RetryReplayAlarm.scheduleAfter(context, RetryReplayAlarm.DEFER_RETRY_MS)
            return
        }
        val now = System.currentTimeMillis()
        val (replayable, rest) = synchronized(lock) {
            val prefs = prefs(context)
            val items = EmailRetryQueueLogic.parse(
                prefs.getString(SECURE_KEY, "[]") ?: "[]"
            )
            val cleaned = EmailRetryQueueLogic.purge(items, now)
            if (cleaned.size != items.size) {
                prefs.edit().putString(SECURE_KEY, EmailRetryQueueLogic.toJson(cleaned)).commit()
            }
            val due = cleaned.filter { EmailRetryQueueLogic.isReplayable(it, now) }
            if (due.isNotEmpty()) {
                // 立即记为「本轮已取出」（attempts++ + 冷却重排），防触发源风暴下重复重放
                // （与 RetryQueue.replayIfEligible 的取出即递增同一条纪律）
                val bumped = cleaned.map { item ->
                    if (EmailRetryQueueLogic.isReplayable(item, now)) {
                        item.copy(attempts = item.attempts + 1, nextAttemptAt = EmailRetryQueueLogic.nextAttemptAfter(now))
                    } else {
                        item
                    }
                }
                prefs.edit().putString(SECURE_KEY, EmailRetryQueueLogic.toJson(bumped)).commit()
            }
            due to cleaned
        }
        if (replayable.isEmpty()) return
        // T239：取出即重排了冷却，排下一颗闹钟兜底
        RetryReplayAlarm.schedule(context)
        Log.i(TAG, "重放邮件队列：${replayable.size} 条")
        for (item in replayable) {
            sendOne(context, item)
        }
    }

    /** 成功后从队列移除（供 sendOne 与调用方共用） */
    fun removeSuccess(context: Context, itemId: String) {
        val prefs = prefs(context)
        synchronized(lock) {
            val items = EmailRetryQueueLogic.parse(
                prefs.getString(SECURE_KEY, "[]") ?: "[]"
            ).filterNot { it.id == itemId }
            prefs.edit().putString(SECURE_KEY, EmailRetryQueueLogic.toJson(items)).commit()
        }
    }

    private fun sendOne(context: Context, item: EmailRetryItem) {
        if (ChannelMirrorInvalidator.isPending(context)) return
        // 通道已删除/停用/改为不参与 ⇒ 重放无意义：移出队列 + 回传失败，不让条目空转
        val config = EmailManager.findChannelById(context, item.configId)
        if (config == null) {
            Log.w(TAG, "重放跳过：邮件通道已删除/停用 configId=${item.configId}")
            removeSuccess(context, item.id)
            if (item.recordId.isNotEmpty()) {
                DeliveryNotifier.notify(
                    context,
                    item.recordId,
                    "EMAIL",
                    WebhookResponseParser.ParseResult(
                        WebhookResponseParser.DeliveryStatus.BIZ_FAIL, 0,
                        "自动补发失败：邮件通道已删除或停用", false
                    ),
                )
            }
            return
        }
        // ⚠ SMTP I/O 不许在调用线程跑：闹钟到点走的是主线程（BroadcastReceiver.onReceive），
        // 直发就是 NetworkOnMainThreadException（2026-11-07 真机实证：15:29:39 那轮补发
        // "发送失败: "空消息即此因）。与 EmailSender.sendNotification 的 IO 协程同一纪律。
        Thread {
            val (success, msg) = EmailSender.resend(config, item.subject, item.body)
            if (success) {
                removeSuccess(context, item.id)
                if (item.recordId.isNotEmpty()) {
                    DeliveryNotifier.notify(
                        context,
                        item.recordId,
                        "EMAIL",
                        WebhookResponseParser.ParseResult(
                            WebhookResponseParser.DeliveryStatus.SUCCESS, 0,
                            "邮件发送成功（自动补发）", false
                        ),
                    )
                }
                Log.i(TAG, "邮件重放成功: configId=${item.configId} record=${item.recordId}")
            } else {
                Log.w(TAG, "邮件重放仍失败（attempts=${item.attempts}）: configId=${item.configId} → $msg")
            }
        }.start()
    }
}
