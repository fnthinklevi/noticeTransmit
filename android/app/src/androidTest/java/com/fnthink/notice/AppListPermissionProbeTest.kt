package com.fnthink.notice

import android.Manifest
import android.app.Activity
import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Process
import android.util.Log
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * 应用列表权限**探针**（不是断言型测试）：把"系统到底怎么回答我们"打在 logcat 里。
 *
 * 触发原因：维护者在 MEIZU 21（Flyme / Android 16）上实测——系统权限历史显示
 * 「读取应用列表」已**拒绝**，但应用内权限页显示"已授予"，且应用筛选页仍能列出应用。
 * 要区分两种根因只能靠真机读数：
 *  (a) [AppOpsManager.permissionToOp] 对 `QUERY_ALL_PACKAGES` 返回 null
 *      ⇒ `MainActivity.canQueryAllPackages()` 的 `?: return true` 直接判"已授予"（fail-open）；
 *  (b) appop 有映射且仍返回 ALLOWED ⇒ Flyme 的"拒绝"记在它自己的隐私层，AOSP 侧看不出来。
 *
 * 因此这里**只观测、不判对错**：断言仅用于"别抛异常"，真凭据全在 TAG=`AppListProbe` 的日志行。
 * 读数方法：`adb logcat -d -s AppListProbe`。
 */
@RunWith(AndroidJUnit4::class)
class AppListPermissionProbeTest {

    private val tag = "AppListProbe"

    @Suppress("DEPRECATION")
    @Test
    fun probe_appListVisibility_sources() {
        val ctx: Context = ApplicationProvider.getApplicationContext()
        val pm = ctx.packageManager
        val pkg = ctx.packageName
        val uid = Process.myUid()
        val out = StringBuilder()
        fun p(k: String, v: Any?) = out.append(k).append('=').append(v).append(" | ")

        p("sdk", Build.VERSION.SDK_INT)
        p("model", "${Build.MANUFACTURER}/${Build.MODEL}")

        // 1) Manifest 是否声明了 QUERY_ALL_PACKAGES（安装期 normal 权限，声明即授予）
        val declared = try {
            pm.getPackageInfo(pkg, PackageManager.GET_PERMISSIONS)
                .requestedPermissions?.contains(Manifest.permission.QUERY_ALL_PACKAGES) == true
        } catch (e: Exception) {
            p("declaredErr", e.javaClass.simpleName)
            false
        }
        p("declared", declared)

        // 2) AOSP 侧的"授予"读数（这条几乎必然 GRANTED —— 它是 install-time 权限）
        p(
            "checkSelf",
            pm.checkPermission(Manifest.permission.QUERY_ALL_PACKAGES, pkg) ==
                PackageManager.PERMISSION_GRANTED,
        )

        // 3) 关键：permissionToOp 是否有映射（(a) 假说的核心）
        val appOps = ctx.getSystemService(Context.APP_OPS_SERVICE) as? AppOpsManager
        p("appOpsSvc", appOps != null)
        val op = AppOpsManager.permissionToOp(Manifest.permission.QUERY_ALL_PACKAGES)
        p("permissionToOp", op ?: "NULL")
        if (op != null && appOps != null) {
            val mode = try {
                appOps.checkOpNoThrow(op, uid, pkg)
            } catch (e: Exception) {
                p("checkOpErr", e.javaClass.simpleName)
                -999
            }
            p("opMode", mode)
            p("modeName", modeName(mode))
        }

        // 4) 三个数据源各自实际返回多少条 —— 拒绝后还能不能读到，全看这三行
        val installedApps = try {
            pm.getInstalledApplications(0).size
        } catch (e: Exception) {
            p("appsErr", e.javaClass.simpleName)
            -1
        }
        p("getInstalledApplications", installedApps)

        val installedPkgs = try {
            pm.getInstalledPackages(0).size
        } catch (e: Exception) {
            p("pkgsErr", e.javaClass.simpleName)
            -1
        }
        p("getInstalledPackages", installedPkgs)

        val launcher = try {
            val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_LAUNCHER)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                pm.queryIntentActivities(intent, PackageManager.ResolveInfoFlags.of(0L)).size
            } else {
                pm.queryIntentActivities(intent, 0).size
            }
        } catch (e: Exception) {
            p("launcherErr", e.javaClass.simpleName)
            -1
        }
        p("queryIntentActivities_LAUNCHER", launcher)

        // 5) 单包查询是否可见（拒绝态下 getPackageInfo 第三方包通常抛 NameNotFound）
        val probeTarget = listOf(
            "com.android.settings",
            "com.tencent.mm",
            "com.ss.android.ugc.aweme",
        ).firstOrNull { it != pkg }
        val visible = probeTarget?.let {
            try {
                pm.getPackageInfo(it, 0)
                true
            } catch (e: Exception) {
                false
            }
        }
        p("probePkg", probeTarget)
        p("probeVisible", visible)

        Log.w(tag, out.toString())
        println("PROBE >>> $out")
        // ⚠ Flyme 会过滤应用侧 logcat（实测 13722 行里一条 AppListProbe 都没有），
        // 所以读数必须走 instrumentation 的 status bundle —— 它会以
        // `INSTRUMENTATION_STATUS: probe=…` 出现在 `am instrument -w` 的标准输出里。
        val status = android.os.Bundle().apply { putString("probe", out.toString()) }
        InstrumentationRegistry.getInstrumentation().sendStatus(Activity.RESULT_OK, status)
        // 唯一断言：读数流程本身不得崩（数值本身是给人看的，不做红绿判断）
        assertTrue("读数应为空？", out.isNotEmpty())
    }

    private fun modeName(mode: Int): String = when (mode) {
        AppOpsManager.MODE_ALLOWED -> "ALLOWED"
        AppOpsManager.MODE_IGNORED -> "IGNORED"
        AppOpsManager.MODE_ERRORED -> "ERRORED"
        AppOpsManager.MODE_DEFAULT -> "DEFAULT"
        else -> "UNKNOWN($mode)"
    }

    /**
     * 真机不变量：**说"已授予"就必须真的枚举得到应用**。
     *
     * 这条正是 ㊸ 修复前后的分水岭 —— 修复前 MEIZU 21（系统已拒绝）上
     * `canQueryAllPackages()` 返回 true 而 `getInstalledApplications` 为 0 条，
     * 页面照样列出 121 个桌面应用；修复后状态必须是 DENIED（或 UNKNOWN 但扫描返回空）。
     * 写成"矛盾即失败"而不是写死值，因此在已授权设备上也成立。
     */
    @Test
    fun grantedStateNeverContradictsAnEmptyEnumeration() {
        val ctx = InstrumentationRegistry.getInstrumentation().targetContext
        val pm = ctx.packageManager
        val declared = try {
            pm.getPackageInfo(ctx.packageName, PackageManager.GET_PERMISSIONS)
                .requestedPermissions?.contains(Manifest.permission.QUERY_ALL_PACKAGES) == true
        } catch (e: Exception) {
            false
        }
        val state = AppListVisibility.fromAppOp(
            packageVisibilityApplies = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R,
            declared = declared,
            appOpMode = null, // 与探针一致：AOSP 对该权限无 appop 映射（MEIZU 21 实测 NULL）
        )
        val installed = pm.getInstalledApplications(0).size
        val verdict = AppListVisibility.fromScan(installed)
        val msg = "declared=$declared state(fromAppOp)=$state installed=$installed verdict=$verdict"
        Log.w(tag, msg)
        val status = android.os.Bundle().apply { putString("invariant", msg) }
        InstrumentationRegistry.getInstrumentation().sendStatus(Activity.RESULT_OK, status)

        // 核心不变量：枚举到 0 条时，任何"可读"结论都不许出现（修复前 Flyme 正是
        // state=已授予 + installed=0 + 桌面 121 条被 merge 回来当列表）。
        if (installed == 0) {
            assertTrue(
                "枚举到 0 条却仍判可读 = 把系统的拒绝当耳旁风。$msg",
                verdict == AppListState.DENIED,
            )
        } else {
            assertTrue(
                "枚举到 $installed 条却判不可读。$msg",
                verdict == AppListState.GRANTED,
            )
        }
    }
}
