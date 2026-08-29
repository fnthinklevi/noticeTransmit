package com.fnthink.notice

import android.content.Context
import android.database.ContentObserver
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch

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

        private val PROJECTION = arrayOf("_id", "address", "body", "date", "type")
    }

    override fun onChange(selfChange: Boolean) {
        onChange(selfChange, null)
    }

    override fun onChange(selfChange: Boolean, uri: Uri?) {
        // 短信入库过程中 onChange 会连续触发多次，下沉到后台串行处理
        CoroutineScope(Dispatchers.IO).launch {
            try {
                scanNewSms()
            } catch (e: Exception) {
                Log.w(TAG, "扫描短信库失败: ${e.message}")
            }
        }
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
        val cursor = context.contentResolver.query(
            Uri.parse(SMS_INBOX_URI), PROJECTION, null, null, "_id DESC"
        ) ?: return

        var newLastId = lastId
        var scanned = 0
        cursor.use {
            while (it.moveToNext() && scanned < MAX_SCAN) {
                val id = it.getLong(0)
                if (id <= lastId) break
                scanned++
                if (id > newLastId) newLastId = id

                // 仅处理收到的短信，忽略已发送/草稿等
                if (it.getInt(4) != TYPE_INBOX) continue

                val address = it.getString(1) ?: I18n.unknownSender()
                val body = it.getString(2) ?: continue
                val date = it.getLong(3)

                SmsDispatcher.handle(
                    context = context,
                    sender = address,
                    message = body,
                    timestamp = date,
                    simInfo = null,
                    source = "observer"
                )
            }
        }
        if (newLastId > lastId) saveLastId(newLastId)
    }

    private fun queryLatestId(): Long {
        val cursor = context.contentResolver.query(
            Uri.parse(SMS_INBOX_URI), arrayOf("_id"), null, null, "_id DESC"
        ) ?: return 0L
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
