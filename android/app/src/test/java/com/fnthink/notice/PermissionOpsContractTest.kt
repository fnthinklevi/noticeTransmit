package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * P1-2：权限/系统设置实现从 `MainActivity` 搬进 `PermissionOps` 后的装配守卫。
 *
 * 这一刀最怕的不是编译错，而是「两处各留一份」：Activity 里那半没删干净、Handler 还指着旧的，
 * 编译照样过、方法名契约测试也照样绿（它只看 `when` 分支），只有真机上某一发权限申请
 * 打到了空实现或旧实现才会现形。所以这里同时钉三件事：
 *  - 实现只在新文件里（Activity 不能再长出同名方法/同一份请求码）；
 *  - Handler 走 `permissionOps`，不再直接调 Activity 的权限方法；
 *  - 请求码单一作者，`onRequestPermissionsResult` 引用同一常量。
 */
class PermissionOpsContractTest {

    private val repoRoot: File = run {
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull {
            File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory
        } ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun source(path: String): String {
        val f = File(repoRoot, path)
        assertTrue("源文件不存在: ${f.absolutePath}", f.isFile)
        return stripComments(f.readText())
    }

    private fun mainActivity() = source("android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt")

    private fun permissionOps() = source("android/app/src/main/kotlin/com/fnthink/notice/PermissionOps.kt")

    private fun handler() =
        source("android/app/src/main/kotlin/com/fnthink/notice/channels/PermissionChannelHandler.kt")

    @Test
    fun `MainActivity 不再保留权限实现与请求码`() {
        val src = mainActivity()
        for (needle in listOf(
            "ActivityCompat.requestPermissions",
            "internal fun requestSmsPermission(",
            "internal fun requestPhonePermission(",
            "internal fun requestCallLogPermission(",
            "internal fun requestLocationPermission(",
            "internal fun requestPromotedNotificationPermission(",
            "internal fun requestNotificationListenerPermission(",
            "internal fun requestPostNotificationPermission(",
            "internal fun isSmsPermissionGranted(",
            "internal fun isPhonePermissionGranted(",
            "internal fun isCallLogPermissionGranted(",
            "internal fun isLocationPermissionGranted(",
            "internal fun isNotificationListenerPermissionGranted(",
            "internal fun isPostNotificationPermissionGranted(",
            "internal fun isPromotedNotificationPermissionGranted(",
            "internal fun isIgnoringBatteryOptimizations(",
            "internal fun openAppDetailsSettings(",
            "internal fun requestBatteryOptimization(",
            "internal fun openInboxChannelSettings(",
            "internal fun canScheduleExactAlarms(",
            "internal fun requestExactAlarmPermission(",
        )) {
            assertFalse(
                "MainActivity 仍保留 `$needle` ⇒ 权限实现出现了第二份作者",
                src.contains(needle),
            )
        }
        for (code in listOf(
            "REQUEST_SMS_PERMISSION =",
            "REQUEST_PHONE_PERMISSION =",
            "REQUEST_POST_NOTIFICATION_PERMISSION =",
            "REQUEST_CALL_LOG_PERMISSION =",
            "REQUEST_LOCATION_PERMISSION =",
        )) {
            assertFalse(
                "请求码 `$code` 仍写在 MainActivity ⇒ 两处各写一份时回传判据会漂",
                src.contains(code),
            )
        }
    }

    @Test
    fun `PermissionOps 收齐全部权限方法与五个请求码`() {
        val src = permissionOps()
        for (needle in listOf(
            "class PermissionOps(private val activity: Activity)",
            "fun requestSmsPermission(",
            "fun requestPhonePermission(",
            "fun requestCallLogPermission(",
            "fun requestLocationPermission(",
            "fun requestQueryAllPackagesPermission(",
            "fun isNotificationListenerPermissionGranted(",
            "fun requestNotificationListenerPermission(",
            "fun isPostNotificationPermissionGranted(",
            "fun requestPostNotificationPermission(",
            "fun requestPromotedNotificationPermission(",
            "fun isPromotedNotificationPermissionGranted(",
            "fun isIgnoringBatteryOptimizations(",
            "fun isSmsPermissionGranted(",
            "fun isPhonePermissionGranted(",
            "fun isCallLogPermissionGranted(",
            "fun isLocationPermissionGranted(",
            "fun requestBatteryOptimization(",
            "fun openInboxChannelSettings(",
            "fun requestXiaomiAutoStart(",
            "fun requestMeizuBackground(",
            "fun requestHuaweiLaunch(",
            "fun requestOppoBackground(",
            "fun requestVivoBackground(",
            "fun openAppDetailsSettings(",
            "fun canScheduleExactAlarms(",
            "fun requestExactAlarmPermission(",
            "ExactAlarmPolicy.allowed(activity)",
        )) {
            assertTrue("PermissionOps 缺少 `$needle`", src.contains(needle))
        }
        for (code in listOf(
            "REQUEST_SMS_PERMISSION = 1001",
            "REQUEST_PHONE_PERMISSION = 1002",
            "REQUEST_POST_NOTIFICATION_PERMISSION = 1003",
            "REQUEST_CALL_LOG_PERMISSION = 1004",
            "REQUEST_LOCATION_PERMISSION = 1005",
            "PROMOTED_PERMISSION_REQUEST_CODE = 9101",
        )) {
            assertEquals("请求码 `$code` 必须只定义一次", 1, Regex(Regex.escape(code)).findAll(src).count())
        }
        assertFalse(
            "PermissionOps 不许再依赖 MainActivity（那会把拆分退回原样）",
            src.contains(": MainActivity") || src.contains("MainActivity("),
        )
    }

    @Test
    fun `Handler 走 permissionOps，Activity 只转交回传`() {
        val h = handler()
        assertTrue("Handler 没有接 PermissionOps", h.contains("activity.permissionOps"))
        for (needle in listOf(
            "activity.isNotificationListenerPermissionGranted(",
            "activity.isPostNotificationPermissionGranted(",
            "activity.isPromotedNotificationPermissionGranted(",
            "activity.isSmsPermissionGranted(",
            "activity.isPhonePermissionGranted(",
            "activity.isCallLogPermissionGranted(",
            "activity.isLocationPermissionGranted(",
            "activity.isIgnoringBatteryOptimizations(",
            "activity.requestSmsPermission(",
            "activity.requestPhonePermission(",
            "activity.requestBatteryOptimization(",
            "activity.openAppDetailsSettings(",
        )) {
            assertFalse("Handler 仍直接调 `$needle` ⇒ 拆分只做了一半", h.contains(needle))
        }
        val main = mainActivity()
        assertTrue(
            "onRequestPermissionsResult 必须引用 PermissionOps 的请求码",
            main.contains("PermissionOps.REQUEST_SMS_PERMISSION") &&
                main.contains("PermissionOps.REQUEST_PHONE_PERMISSION"),
        )
        assertTrue(
            "MainActivity 必须把 PermissionOps 暴露给 Handler",
            main.contains("internal val permissionOps: PermissionOps = PermissionOps(this)"),
        )
    }
}
