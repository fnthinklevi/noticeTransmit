package com.fnthink.notice

import android.content.ComponentName
import android.content.Context
import android.content.pm.ServiceInfo
import android.os.Build
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * T140 (b) 格③「前台服务类型核一遍」—— 把一次眼检换成可复跑的断言。
 *
 * 为什么要有这一份：常驻前台服务的 `foregroundServiceType` 是**清单声明**与**代码那一发**
 * 两处各写一半的形状（`NotificationMonitorService.startForegroundService()` 按 API 分三档
 * `startForeground(..., type)`）。两处不一致的表现不是编译错误，而是 Android 14+ 上
 * `startForeground` 当场抛 SecurityException ⇒ 监听服务起不来 ⇒ 用户看到的是"通知不转发了"，
 * 而 681 例单测全绿（这是设备侧才现形的那一类，本仓记过几次）。
 *
 * 两条判据各钉一件事，都只读 `PackageManager` 这一份**合并后的**清单（不是源码字面量）：
 *  ① 代码在每一档 API 上要请求的那个 type，必须落在清单声明的掩码里；
 *  ② 清单掩码里不许出现"我们并没有对应运行时权限"的那几类（`location` / `camera` /
 *     `health` / `remoteMessaging`）—— 加了它们就等于声明了一种我们没申请的能力，
 *     而 FGS 类型是 Google Play 审核会逐条读的字段。
 */
@RunWith(AndroidJUnit4::class)
class ForegroundServiceTypeProbeTest {

    private val context: Context = ApplicationProvider.getApplicationContext()

    private fun declaredMask(): Int =
        context.packageManager.getServiceInfo(
            ComponentName(context, NotificationMonitorService::class.java),
            0,
        ).foregroundServiceType

    /** 与生产那一发逐字同形的档位判断（改了代码那一发，这里就该红）。 */
    private fun typeRequestedAt(api: Int): Int = when {
        api >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
        api >= Build.VERSION_CODES.Q -> ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
        else -> 0
    }

    @Test
    fun declaredTypesCoverEveryApiBranchRequest() {
        val mask = declaredMask()
        val probes = intArrayOf(
            Build.VERSION_CODES.TIRAMISU,
            Build.VERSION_CODES.UPSIDE_DOWN_CAKE,
            Build.VERSION_CODES.CUPCAKE,
        )
        for (api in probes) {
            val requested = typeRequestedAt(api)
            if (requested == 0) continue
            assertTrue(
                "API $api 那一发请求的 type=$requested 不在清单声明的掩码 $mask 里 ⇒ " +
                    "startForeground 在该档上会抛 SecurityException（监听服务起不来）",
                mask and requested == requested,
            )
        }
    }

    @Test
    fun declaredTypesContainNothingWeNeverAskPermissionFor() {
        val mask = declaredMask()
        val notOurs = intArrayOf(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_LOCATION,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CAMERA,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_HEALTH,
            ServiceInfo.FOREGROUND_SERVICE_TYPE_REMOTE_MESSAGING,
        )
        val leaked = notOurs.filter { mask and it == it }
        assertEquals(
            "清单里多出了我们没有对应运行时权限的 FGS 类型 $leaked（掩码=$mask）：" +
                "声明一种没申请的能力＝隐私面上的一行不实陈述，且 Play 审核逐条读这个字段",
            emptyList<Int>(),
            leaked,
        )
    }

    @Test
    fun logThisDevicesReading() {
        // 探针那一发：设备读数只有打出来才能对着 dumpsys 比（与 AppListPermissionProbeTest 同族）。
        val mask = declaredMask()
        Log.i(
            "FgsTypeProbe",
            "GATE-FGS api=${Build.VERSION.SDK_INT} declared=$mask " +
                "requested=${typeRequestedAt(Build.VERSION.SDK_INT)} " +
                "agree=${mask and typeRequestedAt(Build.VERSION.SDK_INT) == typeRequestedAt(Build.VERSION.SDK_INT)} " +
                "rom=${Build.MANUFACTURER}/${Build.MODEL}",
        )
    }
}
