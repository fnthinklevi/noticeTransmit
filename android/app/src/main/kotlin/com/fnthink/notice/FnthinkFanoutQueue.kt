package com.fnthink.notice

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject

/**
 * 待转发的幻念通知队列（T94 片4）。
 *
 * **为什么先落队再排引擎，而不是当场发**：幻念那一发的签名私钥在 AndroidKeyStore、
 * 载荷与 nonce 全在 Dart（`FnthinkPresenceWorker` 头注释已经把这件事写成结论 ——
 * 「服务活着不等于 Dart isolate 活着」）。所以原生这一侧能做的只有两件：决定**发哪儿**
 * （[ConfigManager.getFnthinkChannelConfigs] + [ChannelRouting]），以及把这一条**留下来**。
 * 真正发出去的那一发由 [FnthinkFanoutWorker] 起后台引擎去做。
 *
 * 存储选 `FlutterSharedPreferences` 而不是文件：与 [HistoryCache] 同一套路（同步写盘、进程被杀不丢），
 * 而那上面已经存着同样形状的通知正文 —— 这里不是**第一份**明文正文，只是一份**待发**的。
 * 落进这一个文件还有第二个理由：后台那一侧的 Dart isolate 只能读到它（见 [PREFS_NAME]）。
 * 上限 [MAX_PENDING] 条，满了丢最旧：宁可少转几条，也不要在用户没察觉的情况下无限堆积。
 *
 * 一条待发项记的是**这一轮路由判下来的目标集合**，不是"再读一次配置"：
 * 重新读会把"落队之后、发送之前用户改了配置"这件事悄悄改写掉，而送达记录说的是
 * "当时确实要发给这几条"。
 *
 * **取走（读+清）由 Dart 那一侧做**，不在这里给一个 `drain()`：那份队列落在
 * `FlutterSharedPreferences` 就是为了让后台 isolate 用现成的 `SharedPreferences` 读到手，
 * 而"读"与"清"必须由同一侧连着做完 —— 一条发失败的项留在队列里，引擎下一轮会把它再发一遍，
 * 而"这一轮失败了"没有任何人替它记账，于是表现是同一条通知反复转发。
 */
class FnthinkFanoutQueue(private val context: Context) {

    companion object {
        private const val TAG = "FnthinkFanoutQueue"

        /**
         * 落进 **FlutterSharedPreferences**（不是另开一个 prefs 文件）：后台引擎那一侧读的是
         * Dart 的 `SharedPreferences` 实例，它只看得到这一个文件（键名带 `flutter.` 前缀）。
         * 另开一个文件的话，Dart 侧就得再要一扇原生→Dart 的读口，而那扇门只在引擎起起来之后
         * 才存在 —— 于是"怎么把待发项交下去"要么多一条协议，要么只能靠入口参数
         * （本工程的 `DartExecutor.DartCallback` 只有三个构造参数，没有入口参数位）。
         */
        private const val PREFS_NAME = ConfigManager.FLUTTER_PREFS_NAME
        private const val KEY_PENDING = "flutter.fnthink_fanout_pending"

        /**
         * 待发上限。引擎起一次要几秒，几秒里进来的通知会堆在一起；50 条足够把一轮
         * 突发装下，又不至于让"引擎起不来"时的丢弃量变成用户看得见的损失。
         */
        const val MAX_PENDING = 50

        /** 纯函数：把一条并进数组，返回本次丢弃的条数（超出 [maxPending] 从**头部**丢最旧）。 */
        internal fun mergeIntoArray(arr: JSONArray, item: JSONObject, maxPending: Int): Int {
            arr.put(item)
            var dropped = 0
            while (arr.length() > maxPending) {
                arr.remove(0)
                dropped++
            }
            return dropped
        }

        /** 纯函数：坏 JSON 一律退化成空数组（抛在这里等于整个待发队列失效）。 */
        internal fun parseArray(raw: String?): JSONArray = try {
            JSONArray(raw ?: "[]")
        } catch (_: Exception) {
            JSONArray()
        }

        /**
         * 纯函数：把一条通知与本轮目标并成一项待发。
         *
         * 目标为空的项直接返回 null —— 「不落队」比「落一条没有目标的项」好：
         * 后者会让引擎空跑一轮，而空跑的理由（这一轮路由没选中任何幻念通道）在
         * 队列里看不出来。
         */
        internal fun buildItem(
            info: NotificationInfo,
            targets: List<FnthinkChannelConfig>,
            viaBackup: Boolean,
        ): JSONObject? {
            if (targets.isEmpty()) return null
            val arr = JSONArray()
            for (t in targets) {
                arr.put(
                    JSONObject().apply {
                        put("channel_id", t.id)
                        put("target_kind", t.targetKind)
                        put("target", t.target)
                    }
                )
            }
            return JSONObject().apply {
                put("id", info.id)
                put("title", info.title)
                put("content", info.content)
                put("appName", info.appName)
                put("time", info.time)
                put("deviceName", info.deviceName)
                put("viaBackup", viaBackup)
                put("targets", arr)
            }
        }
    }

    private val lock = Any()

    private fun prefs() = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)

    /** 落一条。返回**这次丢了多少条**（0 = 没丢）。 */
    fun enqueue(info: NotificationInfo, targets: List<FnthinkChannelConfig>, viaBackup: Boolean): Int {
        val item = buildItem(info, targets, viaBackup) ?: return 0
        return synchronized(lock) {
            try {
                val p = prefs()
                val arr = parseArray(p.getString(KEY_PENDING, null))
                val dropped = mergeIntoArray(arr, item, MAX_PENDING)
                // 数组与丢弃计数同一次 commit：分两次写会出现"队列写成功、计数没写"
                p.edit().putString(KEY_PENDING, arr.toString()).apply()
                if (dropped > 0) {
                    Log.w(TAG, "待发队列已满 $MAX_PENDING 条，丢弃最旧 $dropped 条")
                }
                dropped
            } catch (e: Exception) {
                Log.e(TAG, "落队失败", e)
                0
            }
        }
    }

    /** 待发条数（诊断与守卫用）。 */
    fun pendingCount(): Int = synchronized(lock) {
        parseArray(prefs().getString(KEY_PENDING, null)).length()
    }
}
