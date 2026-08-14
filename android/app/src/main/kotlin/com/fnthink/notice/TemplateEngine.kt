package com.fnthink.notice

import org.json.JSONObject

/**
 * 推送模板引擎
 *
 * 解决问题：原 WebhookPayloadBuilder 对每种平台只能输出固定格式，用户无法自定义消息样式。
 *
 * 支持的 message_format：
 * - default：回退到平台默认 payload（企微/钉钉/飞书走 buildXxx，不应用模板）
 * - text：纯文本，模板变量替换后的字符串作为 text 内容（平台兼容）
 * - markdown：Markdown 格式（企微/钉钉/飞书走 markdown msgtype，通用 webhook 走 markdown 字段）
 * - json：自定义 JSON 模板，模板中变量被替换后作为 JSON body 发送
 * - xml：XML 格式，作为 application/xml 发送
 *
 * 变量占位符：%appName% %title% %content% %subText% %time% %deviceName%
 *             %packageName% %notifyType% %simInfo% %sender% %phoneNumber%
 *             %timestamp% %durationStr% %callState%
 *
 * 平台兼容性：
 * - 企微/钉钉/飞书：text/markdown 生效（修改 msgtype），其他格式回退默认
 * - 通用 webhook：所有格式均生效（修改 body 或 Content-Type）
 */
object TemplateEngine {
    /**
     * 变量集合（值已格式化为字符串，null → 空串）
     */
    data class Vars(
        val appName: String = "",
        val title: String = "",
        val content: String = "",
        val subText: String = "",
        val time: String = "",
        val deviceName: String = "",
        val packageName: String = "",
        val notifyType: String = "",
        val simInfo: String? = null,
        val sender: String? = null,
        val phoneNumber: String? = null,
        val durationStr: String? = null,
        val callState: String? = null,
        val timestamp: Long = System.currentTimeMillis()
    )

    /**
     * 预置模板（用户 message_template 为空时使用）。
     * key = message_format，value = 模板字符串。
     */
    fun presetTemplate(format: String): String? = when (format) {
        // 预置模板跟随应用语言（I18n），避免英文模式下输出中文标签
        "text" -> "[%appName%] %title%\n%content%\n${I18n.timeLabel()}: %time% · ${I18n.deviceLabel()}: %deviceName%"
        "markdown" -> "## %title%\n> **%appName%** · %time%\n\n%content%\n\n---\n📱 ${I18n.deviceLabel()}: %deviceName%"
        "json" -> """{"title":"%title%","content":"%content%","appName":"%appName%","time":"%time%","deviceName":"%deviceName%","type":"%notifyType%","timestamp":%timestamp%}"""
        "xml" -> "<notification>\n  <title>%title%</title>\n  <content>%content%</content>\n  <appName>%appName%</appName>\n  <time>%time%</time>\n  <deviceName>%deviceName%</deviceName>\n  <type>%notifyType%</type>\n</notification>"
        else -> null
    }

    /**
     * 渲染模板：替换所有变量占位符。
     * @param template 模板字符串（含 %var% 占位符）
     * @param vars 变量集合
     * @return 替换后的字符串；若 template 为空，返回空串
     */
    fun render(template: String, vars: Vars): String {
        if (template.isEmpty()) return ""
        val map = buildMap {
            put("appName", vars.appName)
            put("title", vars.title)
            put("content", vars.content)
            put("subText", vars.subText)
            put("time", vars.time)
            put("deviceName", vars.deviceName)
            put("packageName", vars.packageName)
            put("notifyType", vars.notifyType)
            put("simInfo", vars.simInfo ?: "")
            put("sender", vars.sender ?: "")
            put("phoneNumber", vars.phoneNumber ?: "")
            put("durationStr", vars.durationStr ?: "")
            put("callState", vars.callState ?: "")
            put("timestamp", vars.timestamp.toString())
        }
        var result = template
        for ((k, v) in map) {
            result = result.replace("%$k%", escape(v, template))
        }
        return result
    }

    /**
     * 根据变量值转义：JSON 模板中字符串需转义引号/反斜杠；
     * XML 模板中转义 < > &；其他格式原样返回。
     */
    private fun escape(value: String, template: String): String {
        val trimmed = template.trimStart()
        return when {
            trimmed.startsWith("{") || trimmed.startsWith("[") ->
                value.replace("\\", "\\\\").replace("\"", "\\\"")
            trimmed.startsWith("<") ->
                value
                    .replace("&", "&amp;")
                    .replace("<", "&lt;")
                    .replace(">", "&gt;")
            else -> value
        }
    }

    /**
     * 判断该格式是否为平台原生支持（企微/钉钉/飞书）。
     * - default/text/markdown：平台原生支持（修改 msgtype）
     * - json/xml：平台不支持（回退默认 payload）
     */
    fun isPlatformSupported(format: String): Boolean = when (format) {
        "default", "text", "markdown" -> true
        else -> false
    }

    /**
     * 构造发送给通用 webhook 的 body 与 Content-Type。
     * @return Pair(body, contentType)；format=default 时返回 null（由调用方走默认逻辑）
     */
    fun buildGenericBody(
        format: String,
        template: String,
        vars: Vars
    ): Pair<String, String>? {
        val tpl = if (template.isEmpty()) presetTemplate(format) ?: return null else template
        val rendered = render(tpl, vars)
        val contentType = when (format) {
            "json" -> "application/json; charset=utf-8"
            "xml" -> "application/xml; charset=utf-8"
            else -> "text/plain; charset=utf-8"
        }
        // json/xml 直接发送；text/markdown 走纯文本 body
        return Pair(rendered, contentType)
    }

    /**
     * 构造企微/钉钉/飞书的 payload（包裹在平台 msgtype 结构中）。
     * @param type webhook 平台类型
     * @param format 消息格式（default/text/markdown）
     * @param template 自定义模板
     * @param vars 变量集合
     * @return 平台 payload JSON 字符串；format=default 时返回 null（走默认 buildXxx）
     */
    fun buildPlatformPayload(
        type: WebhookPayloadBuilder.WebhookType,
        format: String,
        template: String,
        vars: Vars
    ): String? {
        if (format == "default") return null
        if (!isPlatformSupported(format)) return null

        val tpl = if (template.isEmpty()) presetTemplate(format) ?: return null else template
        val rendered = render(tpl, vars)

        return when (type) {
            WebhookPayloadBuilder.WebhookType.WECHAT_WORK -> JSONObject().apply {
                put("msgtype", format) // text / markdown
                if (format == "markdown") {
                    put("markdown", JSONObject().apply { put("content", rendered) })
                } else {
                    put("text", JSONObject().apply { put("content", rendered) })
                }
            }.toString()

            WebhookPayloadBuilder.WebhookType.DINGTALK -> JSONObject().apply {
                put("msgtype", format)
                if (format == "markdown") {
                    put("markdown", JSONObject().apply {
                        put("title", vars.title)
                        put("text", rendered)
                    })
                } else {
                    put("text", JSONObject().apply { put("content", rendered) })
                }
            }.toString()

            // 飞书自定义机器人不支持 markdown msg_type（仅 text/post/image/interactive），
            // markdown 格式降级为 text 发送渲染后的文本，保证送达。
            WebhookPayloadBuilder.WebhookType.FEISHU -> JSONObject().apply {
                put("msg_type", "text")
                put("content", JSONObject().apply { put("text", rendered) })
            }.toString()

            WebhookPayloadBuilder.WebhookType.TELEGRAM -> JSONObject().apply {
                put("text", rendered)
            }.toString()

            WebhookPayloadBuilder.WebhookType.BARK -> JSONObject().apply {
                put("title", vars.title)
                put("body", rendered)
            }.toString()

            WebhookPayloadBuilder.WebhookType.GENERIC -> return null
        }
    }
}
