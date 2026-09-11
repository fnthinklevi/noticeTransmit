package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 通道行为特征化快照（golden）——**通道描述符表重构的安全网**。
 *
 * 背景：新增通道要改 6 处散落的 `when` 分支（host 识别 / 通知载荷 / 测试载荷 /
 * 短信载荷 / 电话载荷 / 模板平台 JSON / 响应判定），漏改一处即静默失效。
 * 重构为 `ChannelRegistry` 声明式描述符表前，先用本快照把**当前全部通道 × 全部载荷形态**
 * 的逐字节输出固化下来；重构后必须逐字节一致（仅 `timestamp` 归一化）。
 *
 * 覆盖矩阵：8 通道 × 4 载荷形态（通知/测试/短信/电话）= 32 条载荷
 *         + 8 通道 × 3 响应形态（成功/业务失败/限流或等价）= 24 条解析结果。
 *
 * 快照文件：`android/app/src/test/resources/channel_behavior_golden.json`
 * - 不存在时自动生成并**先失败**（提示人工核对后重跑）——防止「快照缺失即静默通过」。
 * - 快照需与生产行为同步更新时：删除文件 → 重跑生成 → 人工 diff 确认。
 */
class ChannelBehaviorGoldenTest {

    private val repoRoot: File = run {
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull {
            File(it, "android/app/src/test/resources").isDirectory
        } ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private val fixtureFile: File
        get() = File(
            repoRoot,
            "android/app/src/test/resources/channel_behavior_golden.json"
        )

    /** timestamp 每次运行都不同，比对前归一化 */
    private fun norm(s: String): String =
        s.replace(Regex("\"timestamp\"\\s*:\\s*\\d+"), "\"timestamp\":0")

    // ── 固定输入（确定性）──

    private fun payloadMatrix(): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        for (type in WebhookPayloadBuilder.WebhookType.values()) {
            result["notify:${type.name}"] = norm(
                WebhookPayloadBuilder.buildPayload(
                    type = type,
                    title = "测试标题",
                    content = "测试内容",
                    appName = "微信",
                    packageName = "com.tencent.mm",
                    time = "2026-01-01 10:00:00",
                    deviceName = "我的设备",
                    notifyType = "notification",
                    chatId = "12345",
                    extras = mapOf("k1" to "v1"),
                )
            )
            result["test:${type.name}"] = norm(
                WebhookPayloadBuilder.buildTestPayload(type, "我的设备", "12345")
            )
            result["sms:${type.name}"] = norm(
                WebhookPayloadBuilder.buildSmsPayload(
                    type = type,
                    sender = "10086",
                    message = "验证码 1234",
                    time = "2026-01-01 10:00:00",
                    deviceName = "我的设备",
                    simInfo = "卡1，中国移动",
                    simFooter = "卡1，中国移动",
                    chatId = "12345",
                )
            )
            result["call:${type.name}"] = norm(
                WebhookPayloadBuilder.buildCallPayload(
                    type = type,
                    state = "ringing",
                    phoneNumber = "13800138000",
                    time = "2026-01-01 10:00:00",
                    durationStr = "",
                    deviceName = "我的设备",
                    simInfo = "卡1，中国移动",
                    simFooter = "卡1，中国移动",
                    chatId = "12345",
                )
            )
        }
        return result
    }

    /** 各通道的「成功 / 业务失败 / 限流」代表响应（体为确定性常量） */
    private fun parseCases(): List<Triple<WebhookPayloadBuilder.WebhookType, Int, String>> = listOf(
        // 企微/钉钉同构
        Triple(WebhookPayloadBuilder.WebhookType.WECHAT_WORK, 200, """{"errcode":0,"errmsg":"ok"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.WECHAT_WORK, 200, """{"errcode":45009,"errmsg":"api freq out of limit"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.WECHAT_WORK, 200, """{"errcode":93000,"errmsg":"invalid webhook url"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.WECHAT_WORK, 500, """{"errcode":-1}"""),
        Triple(WebhookPayloadBuilder.WebhookType.DINGTALK, 200, """{"errcode":0,"errmsg":"ok"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.DINGTALK, 200, """{"errcode":130101,"errmsg":"send too fast"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.DINGTALK, 200, """{"errcode":310000,"errmsg":"keywords not in content"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.DINGTALK, 429, """{"errcode":88}"""),
        // 飞书
        Triple(WebhookPayloadBuilder.WebhookType.FEISHU, 200, """{"code":0,"msg":"success"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.FEISHU, 200, """{"StatusCode":0,"StatusMessage":"success"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.FEISHU, 200, """{"code":9499,"msg":"rate limit"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.FEISHU, 200, """{"code":19021,"msg":"sign match fail"}"""),
        // 通用
        Triple(WebhookPayloadBuilder.WebhookType.GENERIC, 200, """{"code":0,"message":"ok"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.GENERIC, 200, """{"code":500,"message":"server error"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.GENERIC, 200, """{"status":"received"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.GENERIC, 502, """<html>bad gateway</html>"""),
        // Telegram
        Triple(WebhookPayloadBuilder.WebhookType.TELEGRAM, 200, """{"ok":true,"result":{"message_id":1}}"""),
        Triple(WebhookPayloadBuilder.WebhookType.TELEGRAM, 200, """{"ok":false,"description":"chat not found"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.TELEGRAM, 429, """{"ok":false,"description":"Too Many Requests"}"""),
        // Bark
        Triple(WebhookPayloadBuilder.WebhookType.BARK, 200, """{"code":200,"message":"success"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.BARK, 200, """{"code":400,"message":"bad request"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.BARK, 200, """not-json"""),
        // Server酱 / PushPlus
        Triple(WebhookPayloadBuilder.WebhookType.SERVER_CHAN, 200, """{"code":0,"message":"ok"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.SERVER_CHAN, 200, """{"code":40001,"message":"bad pushkey"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.PUSH_PLUS, 200, """{"code":200,"msg":"请求成功"}"""),
        Triple(WebhookPayloadBuilder.WebhookType.PUSH_PLUS, 200, """{"code":500,"msg":"token 无效"}"""),
    )

    private fun describe(r: WebhookResponseParser.ParseResult): String =
        "status=${r.status} httpCode=${r.httpCode} retryable=${r.retryable} message=${r.message}"

    private fun parseMatrix(): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        parseCases().forEachIndexed { index, (type, code, body) ->
            val parsed = WebhookResponseParser.parse(type, code, body)
            result["parse:$index:${type.name}:$code"] = describe(parsed)
        }
        return result
    }

    // ── 快照读取/生成 ──

    private fun loadOrGenerate(
        payloads: Map<String, String>,
        parses: Map<String, String>,
    ): Pair<Map<String, String>, Map<String, String>> {
        if (!fixtureFile.isFile) {
            val root = JSONObject()
            root.put("payloads", JSONObject(payloads as Map<*, *>))
            root.put("parses", JSONObject(parses as Map<*, *>))
            fixtureFile.parentFile?.mkdirs()
            fixtureFile.writeText(root.toString(2), Charsets.UTF_8)
            throw AssertionError(
                "快照已生成：${fixtureFile.absolutePath}\n" +
                    "请人工核对内容与当前生产行为一致后重跑本测试（此时将执行逐字节比对）。"
            )
        }
        val root = JSONObject(fixtureFile.readText(Charsets.UTF_8))
        fun toMap(key: String): Map<String, String> {
            val obj = root.optJSONObject(key) ?: JSONObject()
            val map = LinkedHashMap<String, String>()
            obj.keys().forEach { k -> map[k] = obj.optString(k) }
            return map
        }
        return toMap("payloads") to toMap("parses")
    }

    @Test
    fun payloads_matchGoldenSnapshot() {
        val actual = payloadMatrix()
        val (golden, _) = loadOrGenerate(actual, parseMatrix())
        assertTrue("快照条目数异常：${golden.size}", golden.size >= 32)
        val drift = actual.filter { (k, v) -> golden[k] != v }
        assertEquals(
            "载荷与快照不一致（${drift.size} 条）。重构必须逐字节等价；" +
                "若为有意的行为变更，删除快照文件重新生成并人工 diff：\n" +
                drift.keys.take(8).joinToString("\n") { k ->
                    "  [$k]\n    期望: ${golden[k]}\n    实际: ${actual[k]}"
                },
            emptyMap<String, String>(),
            drift,
        )
    }

    @Test
    fun parses_matchGoldenSnapshot() {
        val actual = parseMatrix()
        val (_, golden) = loadOrGenerate(payloadMatrix(), actual)
        assertTrue("快照条目数异常：${golden.size}", golden.size >= 24)
        val drift = actual.filter { (k, v) -> golden[k] != v }
        assertEquals(
            "解析结果与快照不一致（${drift.size} 条）：\n" +
                drift.keys.take(8).joinToString("\n") { k ->
                    "  [$k]\n    期望: ${golden[k]}\n    实际: ${actual[k]}"
                },
            emptyMap<String, String>(),
            drift,
        )
    }
}
