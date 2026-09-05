package com.fnthink.notice

import android.content.Context
import android.database.ContentObserver
import android.database.Cursor
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * 短信库兜底监听（第二链路）。
 *
 * 背景：SMS_RECEIVED 广播在国产 ROM 限制、Doze、进程被杀等场景可能丢失，
 * 而短信最终一定会写入系统短信库。本 ContentObserver 捕获广播漏掉的短信，
 * 解决「短信只有单一链路、丢了无法恢复」的结构性风险。
 *
 * 与 SmsReceiver 通过 SmsDispatcher 内的指纹去重，同一条短信只会推送一次。
 * 需要 READ_SMS 权限；未授予时不注册，不影响既有行为。
 */
class SmsObserver(private val context: Context) :
    ContentObserver(Handler(Looper.getMainLooper())) {

    companion object {
        private const val TAG = "SmsObserver"
        private const val SMS_INBOX_URI = "content://sms/inbox"
        private const val PREFS_NAME = "sms_observer_prefs"
        private const val KEY_LAST_ID = "last_sms_id"
        // 单次 onChange 最多回溯条数，避免短信风暴 / 首次基线异常时刷屏
        private const val MAX_SCAN = 20
        // Telephony.Sms.MESSAGE_TYPE_INBOX
        private const val TYPE_INBOX = 1
        // 短信入库过程中 onChange 会连续触发多次，合并为一次扫描
        private const val DEBOUNCE_MS = 400L

        private val PROJECTION_FULL = arrayOf("_id", "address", "body", "date", "type", "subscription_id")
        private val PROJECTION_BASIC = arrayOf("_id", "address", "body", "date", "type")
    }

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val scanMutex = Mutex()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var debounceRunnable: Runnable? = null

    // 个别 ROM 缺 subscription_id 列：首次查询失败后降级基础投影，不再反复重试
    @Volatile
    private var useFullProjection = true

    override fun onChange(selfChange: Boolean) {
        onChange(selfChange, null)
    }

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        // 防抖：入库过程 onChange 连续触发多次，合并为一次扫描；
        // Mutex 串行化，避免并发扫描对同一条短信重复处理。
        debounceRunnable?.let { mainHandler.removeCallbacks(it) }
        val r = Runnable {
            scope.launch { scanMutex.withLock { scanNewSms() } }
        }
        debounceRunnable = r
        mainHandler.postDelayed(r, DEBOUNCE_MS)
    }

    /** 服务注销时调用：取消挂起的扫描任务与协程 */
    fun destroy() {
        debounceRunnable?.let { mainHandler.removeCallbacks(it) }
        debounceRunnable = null
        scope.cancel()
    }

    /** 注册后调用：以当前最新短信 id 为基线，避免把历史短信当作新短信补推 */
    fun markBaseline() {
        try {
            val latest = queryLatestId()
            if (latest > 0) {
                saveLastId(latest)
                Log.i(TAG, "短信基线已初始化: lastId=$latest")
            }
        } catch (e: Exception) {
            Log.w(TAG, "初始化短信基线失败: ${e.message}")
        }
    }

    private fun scanNewSms() {
        val lastId = getLastId()
        val uri = Uri.parse(SMS_INBOX_URI)
        val cursor = openCursor(uri) ?: return

        var newLastId = lastId
        var scanned = 0
        cursor.use {
            while (it.moveToNext() && scanned < MAX_SCAN) {
                val id = it.getLong(0)
                if (id <= lastId) break
                scanned++
                if (id > newLastId) newLastId = id

                // 仅处理收到的短信，忽略已发送/草稿等
                val type = it.getInt(4)
                if (type != TYPE_INBOX) {
                    Log.d(TAG, "跳过非收件箱短信: _id=$id type=$type")
                    continue
                }

                val address = it.getString(1) ?: I18n.unknownSender()
                val body = it.getString(2) ?: continue
                val date = it.getLong(3)

                // SIM 信息：短信库 subscription_id 列经 SimInfoHelper 解析为显示名。
                // 与广播链路对齐，避免兜底链路产生的记录缺 SIM 信息。
                val subIdx = it.getColumnIndex("subscription_id")
                val subId = if (subIdx >= 0 && !it.isNull(subIdx)) it.getInt(subIdx) else -1
                val simInfo = if (subId > 0) {
                    SimInfoHelper.getSimInfoBySubId(context, subId)?.displayLabel
                } else null

                SmsDispatcher.handle(
                    context = context,
                    sender = address,
                    message = body,
                    timestamp = date,
                    simInfo = simInfo,
                    source = "observer"
                )
            }
        }
        if (newLastId > lastId) saveLastId(newLastId)
    }

    /** 打开收件箱游标；全量投影失败（缺列）时自动降级基础投影并记住降级状态 */
    private fun openCursor(uri: Uri): Cursor? {
        if (useFullProjection) {
            val c = safeQuery(uri, PROJECTION_FULL)
            if (c != null) return c
            useFullProjection = false
            Log.w(TAG, "subscription_id 列不可用，降级基础投影")
        }
        return safeQuery(uri, PROJECTION_BASIC)
    }

    private fun safeQuery(uri: Uri, projection: Array<String>): Cursor? = try {
        context.contentResolver.query(uri, projection, null, null, "_id DESC")
    } catch (e: Exception) {
        Log.w(TAG, "查询短信库失败(${projection.size}列): ${e.message}")
        null
    }

    private fun queryLatestId(): Long {
        val cursor = safeQuery(Uri.parse(SMS_INBOX_URI), arrayOf("_id")) ?: return 0L
        cursor.use {
            return if (it.moveToFirst()) it.getLong(0) else 0L
        }
    }

    private fun getLastId(): Long = prefs().getLong(KEY_LAST_ID, 0L)

    private fun saveLastId(id: Long) {
        prefs().edit().putLong(KEY_LAST_ID, id).apply()
    }

    private fun prefs() = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
}
