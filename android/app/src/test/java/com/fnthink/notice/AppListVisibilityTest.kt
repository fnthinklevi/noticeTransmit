package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * `AppListVisibility` 的语义锁（纯 JVM，无需 Robolectric）。
 *
 * 触发原因：维护者在 MEIZU 21 上实测——系统权限历史显示「读取应用列表」**已拒绝**，
 * 应用内权限页却显示"已授予"，且应用筛选页仍能列出 121 个桌面应用。
 * 真机探针读数（`AppListPermissionProbeTest`）：
 * `declared=true / checkSelf=true / permissionToOp=NULL / getInstalledApplications=0 /
 *  getInstalledPackages=1 / queryIntentActivities_LAUNCHER=121`
 * 本类的用例就是照着这组数写的。
 */
class AppListVisibilityTest {

    // ===== 静态信号：不得把"系统不给状态"当成已授予（旧代码的 fail-open） =====

    @Test
    fun noAppOpMapping_isUnknown_notGranted() {
        // MEIZU 21 实测：AOSP 没给 QUERY_ALL_PACKAGES 建 appop 映射 ⇒ permissionToOp 返回 null。
        // 旧实现在这里 `?: return true` ⇒ 权限页恒显"已授予"。
        assertEquals(
            AppListState.UNKNOWN,
            AppListVisibility.fromAppOp(
                packageVisibilityApplies = true,
                declared = true,
                appOpMode = null,
            ),
        )
    }

    @Test
    fun appOpsServiceUnavailable_isUnknown_notGranted() {
        // 取不到 AppOps 服务同样只能算"不知道"，与上面同一条约束（两处 fail-open 之一）。
        val mode: Int? = null
        assertEquals(
            AppListState.UNKNOWN,
            AppListVisibility.fromAppOp(true, true, mode),
        )
    }

    @Test
    fun modesMapToStates_conservatively() {
        val cases = listOf(
            AppListVisibility.MODE_ALLOWED to AppListState.GRANTED,
            AppListVisibility.MODE_DEFAULT to AppListState.UNKNOWN,
            AppListVisibility.MODE_IGNORED to AppListState.DENIED,
            AppListVisibility.MODE_ERRORED to AppListState.DENIED,
            999 to AppListState.DENIED, // 未来新增模式：默认按拒绝处理，不得默认放行
        )
        for ((mode, want) in cases) {
            assertEquals(
                "appOpMode=$mode",
                want,
                AppListVisibility.fromAppOp(true, true, mode),
            )
        }
    }

    @Test
    fun notDeclared_isDenied() {
        assertEquals(
            AppListState.DENIED,
            AppListVisibility.fromAppOp(true, declared = false, AppListVisibility.MODE_ALLOWED),
        )
    }

    @Test
    fun beforeAndroid11_isGranted_becauseFilteringDoesNotExist() {
        // API < 30 没有包可见性过滤：没有"读不到"这回事，不得对老系统显示未授予。
        assertEquals(
            AppListState.GRANTED,
            AppListVisibility.fromAppOp(
                packageVisibilityApplies = false,
                declared = true,
                appOpMode = null,
            ),
        )
    }

    // ===== 实测证据压过推断 =====

    @Test
    fun scanWithZeroInstalledApps_isDenied_evenWhenLauncherLooksVisible() {
        // Flyme 拒绝态：getInstalledApplications=0，而桌面查询仍有 121 条。
        // 定论只看枚举计数 —— 这正是旧探测（桌面数 >= 20 判已授予）判错的地方。
        assertEquals(AppListState.DENIED, AppListVisibility.fromScan(0))
    }

    @Test
    fun scanWithResults_isGranted_evenIfAppOpSaysUnknown() {
        assertEquals(AppListState.GRANTED, AppListVisibility.fromScan(312))
    }

    // ===== 扫描时机：只有明确拒绝才拦，避免启动期弹系统框 =====

    @Test
    fun onlyExplicitDenial_blocksScanning() {
        assertTrue(AppListVisibility.shouldScan(AppListState.GRANTED))
        assertTrue(
            "UNKNOWN 必须允许扫描，否则永远定不了论（权限页会一直卡在「系统不给状态」）",
            AppListVisibility.shouldScan(AppListState.UNKNOWN),
        )
        assertFalse(
            "明确拒绝时不得再枚举：国产 ROM 会在首次枚举时弹系统授权框",
            AppListVisibility.shouldScan(AppListState.DENIED),
        )
    }

    // ===== 跨端契约：wire 形状是 Dart 侧解析依据，改值即改契约 =====

    @Test
    fun wireValuesAreStableContractWithDart() {
        assertEquals("granted", AppListState.GRANTED.wire())
        assertEquals("denied", AppListState.DENIED.wire())
        assertEquals("unknown", AppListState.UNKNOWN.wire())
        assertEquals(AppListState.GRANTED, AppListState.fromWire("granted"))
        // 大小写不敏感（跨端只传小写，但解析不挑）
        assertEquals(AppListState.DENIED, AppListState.fromWire("DENIED"))
        // 未知/缺失值一律退回 UNKNOWN（不得默认已授予）
        assertEquals(AppListState.UNKNOWN, AppListState.fromWire(null))
        assertEquals(AppListState.UNKNOWN, AppListState.fromWire("granted-ish"))
        assertEquals(AppListState.UNKNOWN, AppListState.fromWire(""))
    }
}
