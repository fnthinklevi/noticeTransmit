package com.fnthink.notice

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.Location
import android.location.LocationManager
import androidx.core.content.ContextCompat

/**
 * 「读本机最近一次定位」（T124 片C 的 `location:get`，只在远端发起时用；本机界面不碰它）。
 *
 * 三件写在这里的取舍：
 *  ① **只读「最近一次」**（`getLastKnownLocation`），不主动发起定位请求 ——
 *     远程一发指令就把 GPS/网络定位点起来（`requestLocationUpdates`/`getCurrentLocation`），
 *     制造的是**新的采集**；「最近一次」是这台设备已经有的东西，读它不新增采集面。
 *  ② **FINE 或 COARSE 都算给了**：Android 12+ 的「大致位置」给的是 COARSE ——
 *     那不是拒绝，读数仍然成立，精度随结果带出去（差在哪由读的人自己判）。
 *  ③ **没权限回 null、一条都没有回空表**：两件事在对面读起来不同
 *     （一个该去给权限，一个只是这台没有可读的定位）。
 *
 * ⚠ 本机开关（默认关）不在这里判：那是 Dart 侧 `fnthink.read.location` 那一枚，
 * 关着时连这个方法都不会被调到 —— 默认值只有一个家。
 */
object LocationFix {
    private const val TAG = "LocationFix"

    /** 纯数据（JVM 可测的那一半）：从 android Location 摘出来的三件。 */
    data class FixRow(
        val provider: String,
        val timeMillis: Long,
        val accuracyMeters: Float,
    )

    /** 候选里挑**最新**的那一条的下标；空表回 -1。 */
    fun freshestIndex(rows: List<FixRow>): Int {
        var best = -1
        for (i in rows.indices) {
            if (best < 0 || rows[i].timeMillis > rows[best].timeMillis) best = i
        }
        return best
    }

    /** 候选里挑**最新**的那一条；空表回 null。 */
    fun freshest(rows: List<FixRow>): FixRow? =
        if (rows.isEmpty()) null else rows[freshestIndex(rows)]

    /** FINE 或 COARSE 任一给了就算给了（见文件头 ②）。 */
    fun isGranted(context: Context): Boolean {
        val fine = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_FINE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        val coarse = ContextCompat.checkSelfPermission(
            context,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        ) == PackageManager.PERMISSION_GRANTED
        return fine || coarse
    }

    /**
     * 查一次。回 null = **没查成**（没权限 / 查询抛了），回空表 = 有权限但没有任何最近定位。
     * 不抛：一次查询失败不该让整轮收货崩在半路（与 [SmsSearch] / [CallLogSearch] 同一纪律）。
     */
    fun get(context: Context): Map<String, Any?>? {
        if (!isGranted(context)) return null
        return try {
            val lm = context.getSystemService(Context.LOCATION_SERVICE) as? LocationManager
                ?: return emptyMap()
            val rows = mutableListOf<FixRow>()
            val locations = mutableListOf<Location>()
            for (provider in listOf(
                LocationManager.GPS_PROVIDER,
                LocationManager.NETWORK_PROVIDER,
                LocationManager.PASSIVE_PROVIDER,
            )) {
                // ⚠ 逐个 provider 各自 try：某一家的近况（比如 GPS provider 被整台禁用）
                //   不该把另外两家已经取到的读数一起带下水。
                val loc: Location? = try {
                    lm.getLastKnownLocation(provider)
                } catch (e: SecurityException) {
                    null
                } catch (e: Exception) {
                    null
                }
                if (loc != null) {
                    rows.add(FixRow(provider, loc.time, loc.accuracy))
                    locations.add(loc)
                }
            }
            val best = freshestIndex(rows)
            if (best < 0) return emptyMap()
            val loc = locations[best]
            mapOf(
                "lat" to loc.latitude,
                "lon" to loc.longitude,
                "accuracyMeters" to loc.accuracy.toDouble(),
                "provider" to rows[best].provider,
                "timeMillis" to loc.time,
            )
        } catch (e: SecurityException) {
            android.util.Log.w(TAG, "定位读取权限被拒", e)
            null
        } catch (e: Exception) {
            android.util.Log.e(TAG, "定位读取失败", e)
            null
        }
    }
}
