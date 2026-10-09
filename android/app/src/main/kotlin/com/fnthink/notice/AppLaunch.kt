package com.fnthink.notice

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri

/**
 * 「打开本机登记过的一条入口」（T124 片B 的 `app:launch`）。
 *
 * 这是维护者裁定的那两条合法路**唯一的落点**：目标只可能是
 * ① 那枚 App 自己公开的 **deeplink**（一条带 scheme 的 URI），或
 * ② 用户在本机**自己登记**的**组件名**（`pkg/cls`）。
 * ⚠ 普通应用读不到别的 App 的 shortcuts，也**不许**用无障碍模拟点击去"替用户点"——
 * 那等于把整台设备交给对面。这里只做上面那两件事。
 *
 * 三件写在旁边的取舍：
 *  ① **解析是纯函数**（[parseTarget]）：JVM 上能逐条钉"哪种串算数、哪种不算"，
 *     而真机只负责"交给系统"的那一步。
 *  ② **两种形态靠冒号与斜杠的先后分**：`pkg/cls` 的斜杠在冒号之前；URI 一定带 scheme（有冒号）。
 *     分不清就回 null —— 放行一个"看着像"的串，点下去才知道系统不认，而那时指令已经执行过了。
 *  ③ **打不开回 false 不抛**：与显示那几发同一条纪律（一条坏指令不许让整轮收货崩在半路）。
 */
object AppLaunch {

    /** 解析出来的目标（两种合法形态各一支）。 */
    sealed class Target {
        data class Component(val pkg: String, val cls: String) : Target()

        data class Uri(val uri: String) : Target()
    }

    /**
     * 解析（纯函数）。回 null = **这个串不是一个合法目标**（不猜、不补全）。
     */
    fun parseTarget(raw: String): Target? {
        val t = raw.trim()
        if (t.isEmpty() || t.length > MAX_TARGET_CHARS) return null
        for (c in t) {
            if (c.isWhitespace() || c.isISOControl()) return null
        }
        val slash = t.indexOf('/')
        val colon = t.indexOf(':')
        // 组件形态：`pkg/cls`（斜杠在冒号之前；斜杠不能在头）
        if (slash > 0 && (colon < 0 || slash < colon)) {
            val pkg = t.substring(0, slash)
            val cls = t.substring(slash + 1)
            if (cls.isEmpty() || !pkg.contains('.')) return null
            return Target.Component(pkg, cls)
        }
        // URI 形态：scheme 必须合法（字母开头，其后字母/数字/+/-/.）
        if (colon > 0) {
            val scheme = t.substring(0, colon)
            if (SCHEME_RE.matches(scheme)) return Target.Uri(t)
        }
        return null
    }

    /** 真去打开。回 false = **没打开**（系统不认这条 target / 被拦），不抛。 */
    fun launch(context: Context, raw: String): Boolean {
        val target = parseTarget(raw) ?: return false
        return try {
            val intent = when (target) {
                is Target.Component ->
                    Intent().setClassName(target.pkg, target.cls)
                is Target.Uri ->
                    Intent(Intent.ACTION_VIEW, Uri.parse(target.uri))
            }
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            false
        } catch (e: SecurityException) {
            false
        } catch (e: Exception) {
            android.util.Log.e("AppLaunch", "打开登记入口失败", e)
            false
        }
    }

    /** target 串的长度上限（URI 可能很长，但总得有个头；超出的一律不认）。 */
    const val MAX_TARGET_CHARS = 512

    private val SCHEME_RE = Regex("^[A-Za-z][A-Za-z0-9+.\\-]*$")
}
