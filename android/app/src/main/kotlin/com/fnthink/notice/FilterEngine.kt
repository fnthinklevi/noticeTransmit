package com.fnthink.notice

import android.util.Log

/**
 * 统一过滤引擎
 *
 * 三条通知链路（通知栏 / SMS / Call）全部经过本引擎过滤，避免 SmsReceiver/PhoneCallReceiver
 * 绕过黑白名单导致"黑名单有时完全不工作"的问题。
 *
 * 过滤优先级（高到低）：
 * 1. 黑名单关键词命中 → 拦截（最高优先级，即使白名单也命中也要拦截）
 * 2. 白名单关键词命中 → 放行（明确关注的词，无视应用过滤）
 * 3. 应用过滤（仅对 notification 生效，sms/call 不走应用过滤）
 *    - block 模式：enabledPackages 中的包名 → 拦截
 *    - allow 模式：enabledPackages 非空且未包含该包名 → 拦截
 * 4. 默认放行
 *
 * 关键词标准化：trim + 全角转半角 + 折叠连续空白
 * 关键词支持 re: 前缀走正则匹配（大小写不敏感）
 */
object FilterEngine {
    private const val TAG = "FilterEngine"

    /**
     * 标准化关键词与文本：去首尾空白 + 全角转半角 + 折叠连续空白 + 小写化
     */
    fun normalize(raw: String): String {
        if (raw.isEmpty()) return raw
        var s = raw.trim()
        // 全角转半角（空格 + ASCII 可见字符）
        val sb = StringBuilder(s.length)
        for (c in s) {
            when {
                c == '\u3000' -> sb.append(' ') // 全角空格
                c in '\uFF01'..'\uFF5E' -> sb.append((c.code - 0xFEE0).toChar()) // 全角!-~ → 半角
                else -> sb.append(c)
            }
        }
        s = sb.toString()
        // 折叠连续空白
        s = s.replace(Regex("\\s+"), " ")
        return s.lowercase()
    }

    /**
     * 检查单个关键词是否命中已标准化的文本。
     * 支持 re: 前缀走正则匹配（大小写不敏感）。
     */
    fun matchKeyword(normalizedText: String, rawKeyword: String): Boolean {
        val keyword = normalize(rawKeyword)
        if (keyword.isEmpty()) return false

        if (keyword.startsWith("re:")) {
            val pattern = keyword.substring(3)
            if (pattern.isEmpty()) return false
            // E1：超长正则直接拒绝，防灾难性回溯阻塞通知处理协程
            if (pattern.length > 200) {
                Log.w(TAG, "正则超长拒绝（>200 字符）: '${pattern.take(30)}...'")
                return false
            }
            return try {
                Regex(pattern, RegexOption.IGNORE_CASE).containsMatchIn(normalizedText)
            } catch (e: Exception) {
                Log.w(TAG, "Invalid regex keyword '$rawKeyword': ${e.message}")
                false
            }
        }
        return normalizedText.contains(keyword)
    }

    /**
     * 统一过滤入口。
     *
     * @param sourceType 通知来源：notification / sms / call。sms 与 call 不走应用过滤
     * @param filterMode 应用过滤模式：allow（白名单模式，默认）/ block（黑名单模式）
     */
    fun shouldNotify(
        packageName: String,
        title: String,
        content: String,
        subText: String,
        whitelistKeywords: List<String>,
        enabledPackages: Set<String>,
        blacklistKeywords: List<String>,
        filterMode: String = "allow",
        sourceType: String = "notification"
    ): Boolean {
        val fullText = normalize("$title $content $subText")
        val pkg = packageName.lowercase()

        // 1. 黑名单优先级最高
        for (raw in blacklistKeywords) {
            if (raw.isBlank()) continue
            if (matchKeyword(fullText, raw)) {
                Log.d(TAG, "[$sourceType] 黑名单命中关键词='$raw' pkg=$pkg title='$title'")
                return false
            }
        }

        // 2. 白名单关键词命中 → 直接放行（无视应用过滤）
        for (raw in whitelistKeywords) {
            if (raw.isBlank()) continue
            if (matchKeyword(fullText, raw)) {
                Log.d(TAG, "[$sourceType] 白名单命中关键词='$raw' pkg=$pkg title='$title'")
                return true
            }
        }

        // 3. 应用过滤（仅 notification 生效）
        if (sourceType == "notification") {
            if (filterMode == "block") {
                // 黑名单模式：enabledPackages 中的应用不推送
                if (enabledPackages.contains(packageName)) {
                    Log.d(TAG, "[$sourceType] 应用黑名单命中 pkg=$packageName")
                    return false
                }
            } else {
                // 白名单模式：仅 enabledPackages 中的应用推送
                if (enabledPackages.isNotEmpty() && !enabledPackages.contains(packageName)) {
                    Log.d(TAG, "[$sourceType] 应用白名单未命中 pkg=$packageName")
                    return false
                }
            }
        }

        return true
    }
}
