package com.fnthink.notice

import android.content.Context

/**
 * 远程执行「已在原生侧被撤销」的**跨进程那一半**（片3c-5）。
 *
 * ## 为什么撤销要落在这里，而不是只在 Dart 那边
 * 远程执行发生在**后台轮次**里：收货循环把指令取回来、起一个 10 秒窗口，然后 Dart
 * 可能立刻被系统回收。用户按通知栏那一下「撤销」时，**Dart 那一边不一定在跑**。
 * 若只在 Dart 内存里记，按钮按下去之后要等下一轮收货才有人知道，而那时窗口早走完了
 * —— 表现是"我明明按了撤销，它还是执行了"，而且界面上没有任何痕迹能查。
 *
 * 所以：**原生 Receiver 落盘，Dart 到点动手前问一句**。这一格是那条问句的答案。
 *
 * ## 为什么是落盘而不是静态变量
 * BroadcastReceiver 与 Dart 引擎在同一进程，但**不在同一时刻**（Receiver 会被单独拉起）。
 * 静态变量活不过那次拉起，SharedPreferences 活得过。
 *
 * ## 它只回答「这一条被撤了吗」，不回答「现在执行到哪一步」
 * 执行状态是 Dart 那边的机器事实（那张表）。这里存的是**用户在界面之外按下的那一下**，
 * 混进执行状态就等于让两个读者各自写一份账。
 */
object RemoteExecutionCancelStore {
    private const val PREFS = "fnthink_remote_cancel"
    private const val KEY_PREFIX = "cancelled_"

    /** 窗口最长 60 秒（契约 `delay.maxSeconds`），留 2 倍余量再清一遍。 */
    private const val KEEP_MS = 120_000L

    /** 记下"用户按了撤销"。`execId` 就是那枚通知上的 id（Dart 侧生成的执行主键）。 */
    fun markCancelled(context: Context, execId: String, atMs: Long = System.currentTimeMillis()) {
        if (execId.isEmpty()) return
        prefs(context).edit()
            .putLong(KEY_PREFIX + execId, atMs)
            .apply()
        sweep(context, atMs)
    }

    /**
     * 问一次：这一条被撤了吗？
     *
     * ⚠ **读一次就清掉**（[consume]）：到点动手前问的那一句就是唯一一次机会 ——
     *   留着会让"问一下"变成"看一眼"，而下一轮收货重投同一条指令时它会被误读成
     *   "这次也撤了"，于是重投的那一次静默不执行。
     */
    fun consume(context: Context, execId: String): Boolean {
        if (execId.isEmpty()) return false
        val prefs = prefs(context)
        if (!prefs.contains(KEY_PREFIX + execId)) return false
        prefs.edit().remove(KEY_PREFIX + execId).apply()
        return true
    }

    /** 执行链收了终点（做了/没成/撤了）之后清掉那一枚 —— 不留一个用不上的条目。 */
    fun forget(context: Context, execId: String) {
        if (execId.isEmpty()) return
        prefs(context).edit().remove(KEY_PREFIX + execId).apply()
    }

    /** 清掉早于窗口上限的那些（进程被杀/ROM 清缓存之后可能一直留着）。 */
    private fun sweep(context: Context, nowMs: Long) {
        val prefs = prefs(context)
        val stale = prefs.all.keys
            .filter { it.startsWith(KEY_PREFIX) && nowMs - (prefs.getLong(it, 0L)) > KEEP_MS }
        if (stale.isNotEmpty()) prefs.edit().apply { stale.forEach { remove(it) } }.apply()
    }

    private fun prefs(context: Context) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
