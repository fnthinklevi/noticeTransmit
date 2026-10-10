package com.fnthink.notice.channels

import com.fnthink.notice.DeliveryResultStore
import com.fnthink.notice.HistoryCache
import com.fnthink.notice.MainActivity
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
    // ioScope / postSuccess 由基类提供（handle 跑在平台线程）

    override fun handle(call: MethodCall, result: MethodChannel.Result): Boolean {
        when (call.method) {
            "clearNotificationRecords" -> {
                activity.clearNotificationRecords()
                result.success(true)
            }
            // ⚠ 「syncDailyPushCount」这一发已删（T131）：它把 DB 的**今日记录数**灌成原生
            //   的**当日已推送**基数（同一天还取 maxOf），是那个数字在暂停态下仍然上涨的
            //   第三个作者。现在「当日已推送」的唯一作者在原生扇出那一次，Flutter 无话可同步。
            "drainOfflineCache" -> {
                // Flutter 启动时拉取离线期间缓存的通知（避免软件被杀后历史丢失）
                // drainAll 会解析最多 500 条 JSON 并读写 prefs —— 留在平台线程会卡首帧
                ioScope.launch {
                    val drained = HistoryCache.drainAll(activity.applicationContext)
                    // #94-A：记录与"因缓存满而丢弃的条数"必须一次交付（分开读会漏计），
                    // 所以这里回的是 Map 而不是裸 List。
                    postSuccess(
                        result,
                        mapOf(
                            "records" to drained.records,
                            "dropped" to drained.dropped,
                        ),
                    )
                }
            }
            "drainDeliveryResults" -> {
                // Flutter 启动 / resume 时补偿拉取 Activity 销毁期间丢失的送达结果
                // （广播无人接收时由 DeliveryResultStore 持久化兜底）
                ioScope.launch {
                    postSuccess(
                        result,
                        DeliveryResultStore.drain(activity.applicationContext),
                    )
                }
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
                    // 非强制刷新且缓存新鲜（24h 内）时直接复用缓存，避免每次进页面都全量扫描。
                    // ⚠ 但"明确拒绝"态下不得复用：缓存里可能留着拒前采到的全量清单（㊸ 的修复点）。
                    if (!force && activity.canQueryAllPackages() && activity.isInstalledAppsCacheFresh()) {
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
                    if (activity.lastAppListScanDenied) {
                        // 权限被拒 → 抹掉旧清单，而不是"空结果不覆盖缓存"地留着旧数据
                        activity.clearInstalledAppsCache()
                    } else if (apps.isNotEmpty()) {
                        activity.saveInstalledAppsCache(apps)
                    }
                    postSuccess(result, apps)
                }
            }
            "getCachedInstalledApps" -> {
                // 缓存是 prefs 里最多 300+ 条应用的 JSON，读 + 反序列化不放平台线程
                ioScope.launch { postSuccess(result, activity.getCachedInstalledApps()) }
            }
            "saveInstalledAppsCache" -> {
                val apps = call.argument<List<Map<String, Any?>>>("apps") ?: emptyList()
                ioScope.launch {
                    activity.saveInstalledAppsCache(apps)
                    postSuccess(result, true)
                }
            }
            "getAppNameByPackage" -> {
                val packageName = call.argument<String>("packageName") ?: ""
                // PackageManager 查询，同步 binder 调用
                ioScope.launch {
                    postSuccess(result, activity.getAppNameByPackage(packageName))
                }
            }
            else -> return false
        }
        return true
    }
}
