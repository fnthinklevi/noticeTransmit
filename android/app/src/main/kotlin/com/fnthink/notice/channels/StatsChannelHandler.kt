package com.fnthink.notice.channels

import com.fnthink.notice.DeliveryResultStore
import com.fnthink.notice.HistoryCache
import com.fnthink.notice.MainActivity
import com.fnthink.notice.NotificationMonitorService
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch

/**
 * 历史与统计域：清除通知记录、当日计数同步、离线缓存与送达结果补偿拉取、
 * 「现在推送」手动补推、应用列表缓存（应用过滤/规则条件的数据支撑）与包名反查。
 */
internal class StatsChannelHandler(activity: MainActivity) : ChannelHandler(activity) {
    private val ioScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    /** 切回主线程回传结果（MethodChannel.Result 必须在平台线程调用） */
    private fun postSuccess(result: MethodChannel.Result, value: Any?) {
        android.os.Handler(android.os.Looper.getMainLooper()).post {
            try {
                result.success(value)
            } catch (_: Exception) {
                // Activity 已销毁时忽略
            }
        }
    }

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "clearNotificationRecords" -> {
                activity.clearNotificationRecords()
                result.success(true)
            }
            "syncDailyPushCount" -> {
                // 统一状态栏与 DB 统计：Flutter 启动/恢复时把当日记录数同步为原生计数基数
                val count = call.argument<Int>("count") ?: 0
                val date = call.argument<String>("date") ?: ""
                val today = NotificationMonitorService.todayDateString()
                if (date == today) {
                    // 同一天：取较大值（避免覆盖服务运行期间已累加的计数）
                    NotificationMonitorService.pushCount =
                        maxOf(NotificationMonitorService.pushCount, count)
                } else {
                    NotificationMonitorService.pushCount = count
                    NotificationMonitorService.applyTodayDate(date)
                }
                result.success(true)
            }
            "drainOfflineCache" -> {
                // Flutter 启动时拉取离线期间缓存的通知（避免软件被杀后历史丢失）
                result.success(HistoryCache.drainAll(activity.applicationContext))
            }
            "drainDeliveryResults" -> {
                // Flutter 启动 / resume 时补偿拉取 Activity 销毁期间丢失的送达结果
                // （广播无人接收时由 DeliveryResultStore 持久化兜底）
                result.success(DeliveryResultStore.drain(activity.applicationContext))
            }
            "pushRecordNow" -> {
                // 历史记录"现在推送"：把记录转发给服务手动补推（忽略推送暂停开关）
                val record = call.argument<Map<String, Any?>>("record") ?: emptyMap()
                activity.pushRecordNow(record)
                result.success(true)
            }
            "getInstalledApps" -> {
                // P3：全量扫描在 IO 线程执行（300+ 应用时 getApplicationLabel 累计可达 2 秒，
                // 放 UI 线程会直接冻结界面，表现为进入应用筛选页明显卡顿）。
                // result.success 由 postSuccess 切回主线程调用，满足 MethodChannel 线程约束。
                val force = call.argument<Boolean>("force") ?: false
                ioScope.launch {
                    // 非强制刷新且缓存新鲜（24h 内）时直接复用缓存，避免每次进页面都全量扫描
                    if (!force && activity.isInstalledAppsCacheFresh()) {
                        val cached = activity.getCachedInstalledApps()
                        if (cached.isNotEmpty()) {
                            postSuccess(result, cached)
                            return@launch
                        }
                    }
                    val apps = try {
                        activity.getInstalledApps()
                    } catch (e: Exception) {
                        emptyList()
                    }
                    if (apps.isNotEmpty()) activity.saveInstalledAppsCache(apps)
                    postSuccess(result, apps)
                }
            }
            "getCachedInstalledApps" -> {
                result.success(activity.getCachedInstalledApps())
            }
            "saveInstalledAppsCache" -> {
                val apps = call.argument<List<Map<String, Any?>>>("apps") ?: emptyList()
                activity.saveInstalledAppsCache(apps)
                result.success(true)
            }
            "getAppNameByPackage" -> {
                val packageName = call.argument<String>("packageName") ?: ""
                result.success(activity.getAppNameByPackage(packageName))
            }
            else -> return false
        }
        return true
    }
}
