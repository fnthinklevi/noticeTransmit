package com.fnthink.notice

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.GestureDescription
import android.graphics.Path
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * 真机读数工装（仅 debug 变体，见 `src/debug/AndroidManifest.xml` 那段理由）。
 *
 * 它不是产品能力：release/profile 清单里没有这个服务，也没有任何产品代码读它的文件。
 * 存在的唯一原因是这台 MIUI 对 shell 与 UiAutomation 都收回 `INJECT_EVENTS`，
 * `adb shell input` 不可用；启用本服务后，无障碍连接可以 `dispatchGesture`。
 *
 * 协议（不引入网络/广播，避免再多一道权限面）：轮询应用外部目录里的 `ui_cmd.txt`。
 *  - shell 侧先写 `ui_cmd.tmp`，再 `mv` 成 `ui_cmd.txt`（避免读到半截）；
 *  - 服务读完整份、删掉它，逐行执行，结果追加到 `ui_result.txt`；
 *  - 命令：`tap x y` / `long x y ms` / `swipe x1 y1 x2 y2 ms` /
 *    `key back|home|recents|notifications` / `text 任意文字` / `wait ms` / `dump 文件名`。
 */
class DevUiAccessibilityService : AccessibilityService() {

    private val main = Handler(Looper.getMainLooper())
    private val stamp = SimpleDateFormat("HH:mm:ss.SSS", Locale.US)

    @Volatile private var running = false

    override fun onServiceConnected() {
        super.onServiceConnected()
        running = true
        Thread {
            while (running) {
                try {
                    val dir = getExternalFilesDir(null) ?: break
                    val cmd = File(dir, "ui_cmd.txt")
                    if (cmd.exists()) {
                        val lines = cmd.readLines()
                        cmd.delete()
                        for (line in lines) {
                            val text = line.trim()
                            if (text.isEmpty() || text.startsWith("#")) continue
                            try {
                                run(text, dir)
                            } catch (e: Throwable) {
                                log(dir, "FAILED $text : $e")
                            }
                        }
                    }
                } catch (_: Throwable) {
                    // 读文件失败不终止轮询：下一次写入可能就好了
                }
                Thread.sleep(400)
            }
        }.start()
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) = Unit

    override fun onInterrupt() = Unit

    override fun onDestroy() {
        running = false
        super.onDestroy()
    }

    private fun log(dir: File, line: String) {
        File(dir, "ui_result.txt").appendText("${stamp.format(Date())} $line\n")
    }

    private fun run(line: String, dir: File) {
        val p = line.split(Regex("\\s+"))
        when (p[0]) {
            "tap" -> gesture(dir, line, p[1].toInt(), p[2].toInt(), p[1].toInt(), p[2].toInt(), 50)
            "long" -> gesture(dir, line, p[1].toInt(), p[2].toInt(), p[1].toInt(), p[2].toInt(), p[3].toLong())
            "swipe" -> gesture(
                dir, line,
                p[1].toInt(), p[2].toInt(), p[3].toInt(), p[4].toInt(),
                if (p.size > 5) p[5].toLong() else 300L,
            )
            "key" -> {
                val action = when (p[1]) {
                    "back" -> GLOBAL_ACTION_BACK
                    "home" -> GLOBAL_ACTION_HOME
                    "recents" -> GLOBAL_ACTION_RECENTS
                    "notifications" -> GLOBAL_ACTION_NOTIFICATIONS
                    else -> throw IllegalArgumentException("未知 key: ${p[1]}")
                }
                log(dir, "key ${p[1]} -> ${performGlobalAction(action)}")
            }
            "text" -> {
                val value = line.substringAfter("text ").trim()
                val node = getRootInActiveWindow()?.findFocus(AccessibilityNodeInfo.FOCUS_INPUT)
                val ok = if (node == null) {
                    false
                } else {
                    val args = Bundle().apply {
                        putCharSequence(
                            AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE,
                            value,
                        )
                    }
                    node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
                }
                log(dir, "text \"$value\" -> $ok")
            }
            "wait" -> Thread.sleep(p[1].toLong())
            "dump" -> {
                val out = File(dir, p.getOrElse(1) { "ui_dump.txt" })
                val root = getRootInActiveWindow()
                val sb = StringBuilder()
                dumpNode(root, 0, sb)
                out.writeText(sb.toString())
                log(dir, "dump ${out.name} (${sb.length} chars)")
            }
            else -> throw IllegalArgumentException("未知命令: $line")
        }
    }

    private fun gesture(
        dir: File,
        label: String,
        x1: Int, y1: Int, x2: Int, y2: Int, durationMs: Long,
    ) {
        val path = Path().apply {
            moveTo(x1.toFloat(), y1.toFloat())
            if (x1 != x2 || y1 != y2) lineTo(x2.toFloat(), y2.toFloat())
        }
        val stroke = GestureDescription.StrokeDescription(path, 0, durationMs)
        val description = GestureDescription.Builder().addStroke(stroke).build()
        val latch = CountDownLatch(1)
        var completed = false
        main.post {
            val accepted = dispatchGesture(
                description,
                object : GestureResultCallback() {
                    override fun onCompleted(gestureDescription: GestureDescription?) {
                        completed = true
                        latch.countDown()
                    }

                    override fun onCancelled(gestureDescription: GestureDescription?) {
                        latch.countDown()
                    }
                },
                null,
            )
            if (!accepted) latch.countDown()
        }
        latch.await(3, TimeUnit.SECONDS)
        log(dir, "$label -> dispatched=$completed")
        Thread.sleep(120)
    }

    private fun dumpNode(node: AccessibilityNodeInfo?, depth: Int, sb: StringBuilder) {
        if (node == null) {
            sb.append("  ".repeat(depth)).append("<null>\n")
            return
        }
        val text = node.text?.toString()?.replace('\n', ' ')
        val desc = node.contentDescription?.toString()?.replace('\n', ' ')
        sb.append("  ".repeat(depth))
            .append(node.className)
            .append(" text=\"").append(text ?: "").append('"')
            .append(" desc=\"").append(desc ?: "").append('"')
            .append(" bounds=").append(node.boundsHint())
            .append(" clickable=").append(node.isClickable)
            .append(" editable=").append(node.isEditable)
            .append('\n')
        for (i in 0 until node.childCount) {
            dumpNode(node.getChild(i), depth + 1, sb)
        }
    }

    private fun AccessibilityNodeInfo.boundsHint(): String {
        val r = android.graphics.Rect()
        getBoundsInScreen(r)
        return "[${r.left},${r.top}][${r.right},${r.bottom}]"
    }
}
