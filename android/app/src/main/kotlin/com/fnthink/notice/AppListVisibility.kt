package com.fnthink.notice

/**
 * 「读取已安装应用列表」的可见性状态。
 *
 * 三态而不是布尔，是因为**布尔在这个问题上必然说谎**：
 * `QUERY_ALL_PACKAGES` 是安装期 normal 权限（声明即授予），AOSP 的 permission→AppOps
 * 映射里又没有它（真机实测 `AppOpsManager.permissionToOp(QUERY_ALL_PACKAGES) == null`），
 * 所以"声明了 + 查不到 appop"既不等于已授予、也不等于已拒绝 —— 它只是**不知道**。
 * 旧实现把"不知道"当成"已授予"（两处 `?: return true`），于是权限页在任何
 * Android 11+ 设备上都恒显"已授予"，与系统的拒绝无关。
 */
enum class AppListState {
    /** 有明确证据可读（AppOps ALLOWED，或实测扫描真的枚举到了应用）。 */
    GRANTED,

    /** 有明确证据不可读（未声明、AppOps 拒绝态，或扫描枚举为 0 条）。 */
    DENIED,

    /** 系统不给明确状态：不得据此宣称"已授予"，也不得据此拒绝扫描，交给实测裁决。 */
    UNKNOWN,
    ;

    /** 序列化给 Dart 的形状（跨端契约，改值要同步 `permission_service.dart`）。 */
    fun wire(): String = name.lowercase()

    companion object {
        fun fromWire(value: String?): AppListState = when (value?.lowercase()) {
            "granted" -> GRANTED
            "denied" -> DENIED
            else -> UNKNOWN
        }
    }
}

/**
 * 应用列表可见性的**纯**裁决（不碰 Android API，因此可在 JVM 上穷举测试）。
 *
 * 真机依据（MEIZU 21 / Android 16 / Flyme，`AppListPermissionProbeTest` 实测）：
 * `declared=true`、`checkSelfPermission=GRANTED`、`permissionToOp=NULL`、
 * `getInstalledApplications=0`、`getInstalledPackages=1`、`queryIntentActivities(LAUNCHER)=121`。
 * ⇒ 拒绝在 AOSP 的**枚举**接口上是真生效的，但在**桌面 Activity 查询**上完全不生效；
 * 所以旧代码里"桌面可见数 ≥ 20 就算已授予"的探测（`hasQueryAllPackagesEffective`）
 * 在拒绝态下会给出 121 → 判"已授予"，再被 `getInstalledApps` 当成"补足"数据源返回给用户
 * —— 这就是"系统明确拒绝、应用照样列出"的完整链条。
 */
object AppListVisibility {

    // AppOpsManager 的模式常量在此**本地定义**：纯函数不能在 JVM 测试里加载 android.jar 的
    // AppOpsManager（会抛 "not mocked"）。数值与 AOSP 一致，由 QueryAllPackagesContractTest
    // 的源码守卫核对调用方传进来的确实是 AppOpsManager.MODE_*。
    const val MODE_ALLOWED = 0
    const val MODE_IGNORED = 1
    const val MODE_ERRORED = 2
    const val MODE_DEFAULT = 3

    /**
     * 只看静态信号（是否声明 + AppOps 读数）时的结论。
     *
     * @param packageVisibilityApplies Android 11（API 30）以下没有包可见性过滤，一律可读。
     * @param declared manifest 是否声明了 `QUERY_ALL_PACKAGES`。
     * @param appOpMode `AppOpsManager.checkOpNoThrow` 的读数；null = 系统没给这个权限建映射，
     *                  或取不到 AppOps 服务 —— **这不能当成已授予**（旧代码正是这么错的）。
     */
    fun fromAppOp(
        packageVisibilityApplies: Boolean,
        declared: Boolean,
        appOpMode: Int?,
    ): AppListState = when {
        !packageVisibilityApplies -> AppListState.GRANTED
        !declared -> AppListState.DENIED
        appOpMode == null -> AppListState.UNKNOWN
        appOpMode == MODE_ALLOWED -> AppListState.GRANTED
        appOpMode == MODE_DEFAULT -> AppListState.UNKNOWN
        else -> AppListState.DENIED // IGNORED / ERRORED / 未知模式：明确的拒绝信号
    }

    /**
     * 用一次真实枚举的结果定论：读到东西就是可读，一条都没有就是被过滤。
     *
     * ⚠ 只认 `getInstalledApplications` / `getInstalledPackages` 这类**枚举**计数，
     * 不要拿桌面 Activity 数当证据（见类注释：Flyme 拒绝态下它是 121）。
     */
    fun fromScan(installedCount: Int): AppListState =
        if (installedCount > 0) AppListState.GRANTED else AppListState.DENIED

    /**
     * 是否允许真的去枚举应用列表。
     *
     * 只有**明确拒绝**才拦：国产 ROM（MIUI/澎湃）会在首次枚举时弹系统授权框，
     * 所以启动期的权限检查绝不扫描；而 UNKNOWN 必须靠一次扫描才能定论，
     * 那次扫描只发生在用户主动进入「应用筛选」页时 —— 正是该弹框的位置。
     */
    fun shouldScan(state: AppListState): Boolean = state != AppListState.DENIED
}
