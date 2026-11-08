package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T197 片3 / 发送端秒级的接线守卫。
 *
 * 这一片最危险的失效不是编译错，而是**看起来都还在、实际谁也没接上**：
 * 服务里常驻引擎建了但没人 ensure、通知到了仍走 WorkManager、UI 心跳没人写、
 * `stopLoopOnly` 顺手把闹钟撤了。每一条都只表现为"还是慢/还是收不到"。
 *
 * 因此这里钉四组：
 *  1. 服务 onCreate 起 ensure 环、onDestroy 收引擎；
 *  2. `dispatchFnthink` 走 `FnthinkFanoutNow.request`（不是直接 WorkManager）；
 *  3. 常驻引擎的 Dart 入口确实开 SSE、按心跳接管、接住 `fanoutNow`；
 *  4. 交班用的 `stopLoopOnly` 不许动闹钟（`_presence`）。
 */
class FnthinkServiceEngineContractTest {

    private fun ok(message: String, condition: Boolean) =
        assertTrue(message, condition)

    private fun repoFile(rel: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

    private fun stripComments(src: String): String =
        src.replace(Regex("""/\*[\s\S]*?\*/"""), "")
            .replace(Regex("""//[^\n]*"""), "")

    private fun kt(rel: String) =
        stripComments(
            repoFile("app/src/main/kotlin/com/fnthink/notice/$rel").readText(Charsets.UTF_8),
        )

    private fun dart(rel: String) =
        stripComments(repoFile(rel).readText(Charsets.UTF_8))

    @Test
    fun `服务生命周期：onCreate 起 ensure 环，onDestroy 收常驻引擎`() {
        val service = kt("NotificationMonitorService.kt")
        val loop = service.substringAfter("private fun startFnthinkServiceEngineLoop(")
        ok(
            "服务没有 startFnthinkServiceEngineLoop 调用 ⇒ 常驻引擎永远不会被建",
            service.contains("startFnthinkServiceEngineLoop()"),
        )
        ok(
            "ensure 环里没有 FnthinkServiceEngine.ensure ⇒ 建了也不维护",
            loop.contains("FnthinkServiceEngine.ensure("),
        )
        ok(
            "onDestroy 没有 FnthinkServiceEngine.stop ⇒ 服务走了引擎还挂着",
            service.substringAfter("override fun onDestroy()")
                .contains("FnthinkServiceEngine.stop()"),
        )
    }

    @Test
    fun `通知到达先走常驻引擎，不再直接排 WorkManager`() {
        val dispatch = kt("NotificationMonitorService.kt")
            .substringAfter("private fun dispatchFnthink(")
        ok(
            "dispatchFnthink 没有 FnthinkFanoutNow.request ⇒ 发送端还是等 WorkManager 调度",
            dispatch.contains("FnthinkFanoutNow.request("),
        )
        ok(
            "dispatchFnthink 里仍直接 FnthinkFanoutWorker.schedule ⇒ 绕过了常驻引擎的去重闸",
            !dispatch.contains("FnthinkFanoutWorker.schedule("),
        )
        val engine = kt("FnthinkServiceEngine.kt")
        ok(
            "FnthinkFanoutNow 没有退回 WorkManager 的兜底 ⇒ 引擎没起来时这一条会丢在队列里",
            engine.contains("FnthinkFanoutWorker.schedule("),
        )
    }

    @Test
    fun `常驻引擎入口：开 SSE、按心跳接管、接住 fanoutNow`() {
        val entry = dart("lib/services/fnthink_service_entrypoint.dart")
        ok(
            "常驻入口没有 fnthinkAllowStream = true ⇒ 锁屏时不持 SSE",
            entry.contains("fnthinkAllowStream = true"),
        )
        ok(
            "常驻入口没有 startIfEnabled ⇒ 心跳过期时不会接管收货",
            entry.contains("startIfEnabled()"),
        )
        ok(
            "常驻入口没有 stopLoopOnly ⇒ UI 回来时要么不停、要么把闹钟撤了",
            entry.contains("stopLoopOnly()"),
        )
        ok(
            "常驻入口没有 fanoutNow 处理 ⇒ 原生叫不醒发送",
            entry.contains("fanoutNow") && entry.contains("claimPendingFanoutBatch"),
        )
        ok(
            "常驻入口没有 alive 回报 ⇒ 僵尸引擎不会被重建",
            entry.contains("invokeMethod<void>('alive')"),
        )
        val bridge = dart("lib/services/fnthink_service_bridge.dart")
        ok(
            "UI 心跳键名不在 bridge 里 ⇒ 服务引擎读不到心跳",
            bridge.contains("kFnthinkUiAliveKey = 'fnthink_ui_alive_at'"),
        )
        val coordinator = dart("lib/services/fnthink_receive_coordinator.dart")
        ok(
            "UI 心跳没挂在收货循环上 ⇒ 循环停了心跳仍新鲜、服务引擎不接管",
            coordinator.contains("startFnthinkUiHeartbeat()"),
        )
        ok(
            "UI 心跳没有按 fnthinkBackgroundIsolate 分档 ⇒ 服务引擎会把自己写成 UI 活着",
            coordinator.contains("!fnthinkBackgroundIsolate"),
        )
        ok(
            "stopLoopOnly 没停心跳 ⇒ UI 循环停了心跳仍新鲜",
            coordinator.contains("stopFnthinkUiHeartbeat()"),
        )
        ok(
            "main.dart 又无条件起心跳 ⇒ 循环停了心跳仍新鲜",
            !dart("lib/main.dart").contains("startFnthinkUiHeartbeat"),
        )
        ok(
            "main.dart 没有发布服务引擎 handle",
            dart("lib/main.dart").contains("publishFnthinkServiceHandle"),
        )
    }

    @Test
    fun `交班只停循环，不动闹钟`() {
        val coordinator = dart("lib/services/fnthink_receive_coordinator.dart")
        val stopOnly = coordinator.substringAfter("void stopLoopOnly() {")
            .substringBefore("}")
        ok(
            "stopLoopOnly 里出现了 _presence ⇒ UI 回来时会把 UI 刚排的闹钟撤掉",
            !stopOnly.contains("_presence"),
        )
        ok(
            "stop() 没有复用 stopLoopOnly ⇒ 两份停法会朝不同方向漂",
            coordinator.substringAfter("void stop() {").contains("stopLoopOnly()"),
        )
    }
}
