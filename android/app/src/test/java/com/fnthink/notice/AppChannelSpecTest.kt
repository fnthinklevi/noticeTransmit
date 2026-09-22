package com.fnthink.notice

import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 应用通道模板单元测试（纯逻辑，JVM 直测）。
 * 覆盖：token 响应解析（企微/飞书）、载荷构造（agentid/touser 定向、receive_id）、
 * URL 构造、内容截断、configSchema 完整性。
 * ⚠ 全部使用假凭据字面量（测试专用，非真实凭据）。
 */
class AppChannelSpecTest {

    private fun wecomConfig() = AppChannelConfig(
        id = "app-wecom-1", name = "企微应用", type = AppChannelTypes.WECOM_APP,
        baseUrl = AppChannelTypes.WECOM_OFFICIAL_BASE,
        secret = "corpsecret-demo",
        config = JSONObject().put("corpid", "corp-demo").put("agentid", 1000002).put("touser", "@all"),
        messageFormat = "default", enabled = true,
    )

    private fun feishuConfig() = AppChannelConfig(
        id = "app-feishu-1", name = "飞书应用", type = AppChannelTypes.FEISHU_APP,
        baseUrl = AppChannelTypes.FEISHU_OFFICIAL_BASE,
        secret = "app-secret-demo",
        config = JSONObject()
            .put("app_id", "cli-demo")
            .put("receive_id_type", "chat_id")
            .put("receive_id", "oc-demo"),
        messageFormat = "default", enabled = true,
    )

    // ===== 注册表 =====

    @Test
    fun registry_containsBothAppTypes() {
        assertEquals(
            setOf(AppChannelTypes.WECOM_APP, AppChannelTypes.FEISHU_APP),
            AppChannelRegistry.SPECS.map { it.type }.toSet(),
        )
    }

    // ===== token 响应解析 =====

    @Test
    fun parseWecomToken_ok() {
        val (token, expiresIn) = AppChannelsTokenParsers.parseWecomToken(
            """{"errcode":0,"access_token":"at-1","expires_in":7200}"""
        )
        assertEquals("at-1", token)
        assertEquals(7200, expiresIn)
    }

    @Test
    fun parseWecomToken_errcodeThrows() {
        try {
            AppChannelsTokenParsers.parseWecomToken("""{"errcode":40013,"errmsg":"invalid corpid"}""")
            throw AssertionError("应抛出 TokenFetchException")
        } catch (e: AppChannelTokenManager.TokenFetchException) {
            assertEquals(40013, e.errcode)
        }
    }

    // ===== 非 JSON 响应（网关错误页/空响应）—— 崩溃防护（v1.59）=====

    @Test
    fun parseWecomToken_nonJsonThrowsTokenFetchException() {
        // 回归背景：parseWecomToken 直接 JSONObject(body) 构造，非 JSON 响应
        // （WAF/网关 502 错误页）会抛 JSONException 绕过调用链 catch 冒泡崩溃。
        try {
            AppChannelsTokenParsers.parseWecomToken("<!DOCTYPE html><html>502 Bad Gateway</html>")
            throw AssertionError("非 JSON 响应应抛出 TokenFetchException")
        } catch (e: AppChannelTokenManager.TokenFetchException) {
            assertEquals(-1, e.errcode)
            assertTrue(
                "错误信息应带响应摘要便于排查：${e.message}",
                e.message!!.contains("非 JSON"),
            )
        }
    }

    @Test
    fun parseWecomToken_emptyBodyThrowsTokenFetchException() {
        try {
            AppChannelsTokenParsers.parseWecomToken("")
            throw AssertionError("空响应应抛出 TokenFetchException")
        } catch (e: AppChannelTokenManager.TokenFetchException) {
            assertEquals(-1, e.errcode)
        }
    }

    @Test
    fun parseFeishuToken_nonJsonThrowsTokenFetchException() {
        try {
            AppChannelsTokenParsers.parseFeishuToken("<html>403 Forbidden</html>")
            throw AssertionError("非 JSON 响应应抛出 TokenFetchException")
        } catch (e: AppChannelTokenManager.TokenFetchException) {
            assertEquals(-1, e.errcode)
            assertTrue(
                "错误信息应带响应摘要便于排查：${e.message}",
                e.message!!.contains("非 JSON"),
            )
        }
    }

    @Test
    fun parseFeishuToken_ok() {
        val (token, expire) = AppChannelsTokenParsers.parseFeishuToken(
            """{"code":0,"tenant_access_token":"t-7f1b","expire":7200}"""
        )
        assertEquals("t-7f1b", token)
        assertEquals(7200, expire)
    }

    @Test
    fun parseFeishuToken_errcodeThrows() {
        try {
            AppChannelsTokenParsers.parseFeishuToken("""{"code":99991663,"msg":"bad app id"}""")
            throw AssertionError("应抛出 TokenFetchException")
        } catch (e: AppChannelTokenManager.TokenFetchException) {
            assertEquals(99991663, e.errcode)
        }
    }

    // ===== 载荷构造 =====

    @Test
    fun wecomPayload_textWithAgentidAndTouser() {
        val spec = AppChannelRegistry.spec(AppChannelTypes.WECOM_APP)!!
        val payload = spec.buildPayload(wecomConfig(), "通知内容", false)
        val json = JSONObject(payload)
        assertEquals("text", json.getString("msgtype"))
        assertEquals("通知内容", json.getJSONObject("text").getString("content"))
        assertEquals(1000002L, json.getLong("agentid"))
        assertEquals("@all", json.getString("touser"))
    }

    @Test
    fun wecomPayload_markdownMode() {
        val spec = AppChannelRegistry.spec(AppChannelTypes.WECOM_APP)!!
        val json = JSONObject(spec.buildPayload(wecomConfig(), "内容", true))
        assertEquals("markdown", json.getString("msgtype"))
        assertEquals("内容", json.getJSONObject("markdown").getString("content"))
    }

    @Test
    fun wecomPayload_invalidAgentidThrows() {
        val cfg = wecomConfig().copy(
            config = JSONObject().put("corpid", "corp-demo").put("agentid", 0),
        )
        try {
            AppChannelRegistry.spec(AppChannelTypes.WECOM_APP)!!.buildPayload(cfg, "内容", false)
            throw AssertionError("agentid=0 应抛出 IllegalArgumentException")
        } catch (_: IllegalArgumentException) {
        }
    }

    @Test
    fun feishuPayload_textWithReceiveIdAndNestedContent() {
        val spec = AppChannelRegistry.spec(AppChannelTypes.FEISHU_APP)!!
        val payload = spec.buildPayload(feishuConfig(), "通知内容", false)
        val json = JSONObject(payload)
        assertEquals("text", json.getString("msg_type"))
        assertEquals("oc-demo", json.getString("receive_id"))
        // content 是 JSON 字符串（二次序列化，官方契约）
        val inner = JSONObject(json.getString("content"))
        assertEquals("通知内容", inner.getString("text"))
    }

    @Test
    fun feishuPayload_missingReceiveIdThrows() {
        val cfg = feishuConfig().copy(
            config = JSONObject().put("app_id", "cli-demo").put("receive_id_type", "chat_id"),
        )
        try {
            AppChannelRegistry.spec(AppChannelTypes.FEISHU_APP)!!.buildPayload(cfg, "内容", false)
            throw AssertionError("receive_id 为空应抛出 IllegalArgumentException")
        } catch (_: IllegalArgumentException) {
        }
    }

    // ===== 发送端点 =====

    @Test
    fun wecomSendTarget_carriesAccessTokenInQuery() {
        val spec = AppChannelRegistry.spec(AppChannelTypes.WECOM_APP)!!
        val (url, headers) = spec.sendTarget(wecomConfig(), AppChannelTypes.WECOM_OFFICIAL_BASE, "TK")
        assertEquals("https://qyapi.weixin.qq.com/cgi-bin/message/send?access_token=TK", url)
        assertTrue(headers.isEmpty())
    }

    @Test
    fun feishuSendTarget_carriesReceiveIdTypeInQueryAndBearerHeader() {
        val spec = AppChannelRegistry.spec(AppChannelTypes.FEISHU_APP)!!
        val (url, headers) = spec.sendTarget(feishuConfig(), AppChannelTypes.FEISHU_OFFICIAL_BASE, "TK")
        assertEquals(
            "https://open.feishu.cn/open-apis/im/v1/messages?receive_id_type=chat_id",
            url,
        )
        assertEquals("Bearer TK", headers["Authorization"])
    }

    // ===== 截断 =====

    @Test
    fun wecomTruncate_byBytes2048() {
        val spec = AppChannelRegistry.spec(AppChannelTypes.WECOM_APP)!!
        val longText = "测".repeat(1500) // 4500 字节
        val truncated = spec.truncate(longText)
        assertTrue(truncated.toByteArray(Charsets.UTF_8).size <= 2048)
    }

    @Test
    fun feishuTruncate_byChars3000() {
        val spec = AppChannelRegistry.spec(AppChannelTypes.FEISHU_APP)!!
        val longText = "a".repeat(4000)
        assertEquals(3000, spec.truncate(longText).length)
    }

    // ===== configSchema（驱动 Dart 设置页渲染）=====

    @Test
    fun configSchema_coversRequiredCredentialFields() {
        val wecom = AppChannelRegistry.spec(AppChannelTypes.WECOM_APP)!!
        assertTrue(wecom.configSchema.any { it.key == "corpid" && it.required })
        assertTrue(wecom.configSchema.any { it.key == "agentid" && it.required })
        val feishu = AppChannelRegistry.spec(AppChannelTypes.FEISHU_APP)!!
        assertTrue(feishu.configSchema.any { it.key == "app_id" && it.required })
        assertTrue(feishu.configSchema.any { it.key == "receive_id" && it.required })
    }
    // ===== configSchema 与 payload 消费字段一致性（防漂移）=====

    @Test
    fun configKeysReadByPayloadAreDeclaredInSchema() {
        // 各类型 payload 构造读取的 config key 必须都在 configSchema 声明——
        // 否则 Dart 设置页不会渲染对应输入框，运行期读到默认值（如 touser 静默变 @all、
        // receive_id 为空直接抛错）而配置界面无任何提示。
        val readKeys = mapOf(
            AppChannelTypes.WECOM_APP to listOf("corpid", "agentid", "touser"),
            AppChannelTypes.FEISHU_APP to
                listOf("app_id", "receive_id_type", "receive_id"),
        )
        for ((type, keys) in readKeys) {
            val spec = AppChannelRegistry.spec(type)
            assertNotNull("缺少 spec：$type", spec)
            val declared = spec!!.configSchema.map { it.key }.toSet()
            for (key in keys) {
                assertTrue(
                    "$type 的 payload 读取 config\"$key\" 但 configSchema 未声明" +
                        "（设置页不会渲染该输入框）",
                    key in declared,
                )
            }
        }
    }

    @Test
    fun schemaKeysAreAllConsumedOrOptional() {
        // 反向：schema 声明的字段不应是无消费方的孤儿字段（required 字段尤其）
        for (spec in AppChannelRegistry.SPECS) {
            assertTrue("${spec.type} configSchema 为空", spec.configSchema.isNotEmpty())
            // key 唯一性：重复 key 会导致设置页渲染两个输入框绑定同一字段
            val keys = spec.configSchema.map { it.key }
            assertEquals("${spec.type} configSchema 存在重复 key", keys.size, keys.toSet().size)
        }
    }
}
