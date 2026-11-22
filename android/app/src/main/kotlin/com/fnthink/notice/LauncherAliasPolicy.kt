package com.fnthink.notice

/**
 * 桌面启动别名的安全切换判据（P1-2 后续）。
 *
 * release 包只暴露 activity-alias。应用首启时会把「中文默认图标」切成系统语言对应的那一枚；
 * 如果**当场禁用正在承载当前任务的旧 alias**，系统会把任务送回桌面
 * （`DONT_KILL_APP` 也挡不住，2026-11-22 模拟器实测）。所以从旧 alias 启动的那一程
 * 只能「先启用目标、延迟到 onStop 再禁用其余」。
 *
 * 判据收在这里（纯字符串，无 Android 运行时依赖），MainActivity 只做动作。
 */
internal object LauncherAliasPolicy {
    /**
     * @param launchComponent 当前任务的启动组件（`ComponentName.flattenToString()`）；
     *   null = 不是从本应用的 alias 启动（debug 的 MainActivity / 应用内跳转）。
     * @param target 本次要切到的 alias（同样用 `flattenToString()`）。
     * @return true = 目标与启动组件不同，必须延迟禁用；false = 可以立即全量收敛。
     */
    fun mustDeferDisable(launchComponent: String?, target: String): Boolean =
        launchComponent != null && launchComponent != target
}
