package com.fnthink.notice

import com.fnthink.notice.channels.channelDescriptorsPayload
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test
import java.io.File

/**
 * `getChannelDescriptors` 的导出契约（第 5 步）。
 *
 * Dart 侧的表单字段、类型选择器、secret/模板显隐全部改成读这份导出之后，
 * 原生表与 UI 之间就只剩**这一条边界**：它出错的表现是"表单没有字段""密钥框消失"
 * "类型列表少一项"，而不是编译错误。本类锁四件事：
 * 1. 载荷必须是 MethodChannel standard codec 能过的类型（放 enum / JSONObject 进去
 *    会在运行时抛 IllegalArgumentException，而且只在点开设置页时抛）；
 * 2. key 全局唯一、family 只能是 webhook / app（Dart 按 family 分页渲染）；
 * 3. 能力位必须由描述符事实派生，不能有人另抄一份名单（`secretUsed` 与签名表、
 *    `customTemplate` 与模板策略两两核对）；
 * 4. **导出快照** `channel_descriptors.json` 与生产代码逐字节一致 ——
 *    该文件同时是 Dart widget 测试的 fixture，所以它必须来自原生表本身，
 *    否则测试是在对着一份手抄的假描述符跑绿。
 */
class ChannelDescriptorExportTest {

    private val repoRoot: File = run {
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull {
            File(it, "android/app/src/test/resources").isDirectory
        } ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private val fixtureFile: File
        get() = File(
            repoRoot,
            "android/app/src/test/resources/channel_descriptors.json",
        )

    private val all: List<Map<String, Any?>>
        get() = ChannelRegistry.descriptors() + AppChannelRegistry.descriptors()

    // ── 1. 可序列化 ─────────────────────────────────────────────────────

    private fun serializable(value: Any?): Boolean = when (value) {
        null, is String, is Int, is Long, is Boolean, is Double -> true
        is List<*> -> value.all { serializable(it) }
        is Map<*, *> -> value.keys.all { it is String } && value.values.all { serializable(it) }
        else -> false
    }

    @Test
    fun exportedPayloadIsMethodChannelSerializable() {
        for (d in all) {
            val key = d["key"].toString()
            assertTrue(
                "$key 的顶层键必须是 String（standard codec 的 Map 只接受字符串键）",
                d.keys.all { it is String },
            )
            for ((k, v) in d) {
                assertTrue(
                    "$key.$k 的类型 ${v?.javaClass?.name} 过不了 MethodChannel（会在 Dart 侧抛异常）",
                    serializable(v),
                )
            }
        }
    }

    // ── 2. 标识与族 ─────────────────────────────────────────────────────

    @Test
    fun keysAreUniqueAndFamiliesAreClosed() {
        val keys = all.map { it["key"] as String }
        assertEquals("描述符 key 不得重复", keys.size, keys.toSet().size)
        assertEquals(
            "webhook 12 + 应用通道 2",
            mapOf("webhook" to 12, "app" to 2),
            all.groupBy { it["family"] as String }.mapValues { it.value.size },
        )
        for (d in all) {
            val key = d["key"] as String
            assertTrue("$key 的 key 必须是 slug 口径", Regex("^[a-z][a-z0-9_]*$").matches(key))
            assertEquals(
                "$key 的 iconKey 与 key 必须同值（Dart 图标表按它取）",
                key,
                d["iconKey"],
            )
            assertTrue(
                "$key 没有 labelKey（Dart 取不到名字会退回显示 key 原文）",
                (d["labelKey"] as String).isNotEmpty(),
            )
        }
    }

    // ── 3. 能力位是派生的，不是手抄名单 ─────────────────────────────────

    @Suppress("UNCHECKED_CAST")
    private fun caps(d: Map<String, Any?>) = d["capabilities"] as List<String>

    @Test
    fun secretUsedMatchesWhatActuallyCarriesACredential() {
        // 与 ChannelRegistry.capabilitiesOf 同一条规则的第二次表述：
        // UI 的密钥输入框显隐只看这个位，抄错的名单会让凭据没地方填或多一个没用的框。
        val secretTypes = ChannelRegistry.CHANNELS
            .filter {
                it.signature != SignatureScheme.NONE ||
                    it.transport.secretRequired ||
                    it.transport.secretAsQueryToken
            }
            .map { it.type.name.lowercase() }
            .toSet()
        for (d in all.filter { it["family"] == "webhook" }) {
            val key = d["key"] as String
            assertEquals(
                "$key 的 secretUsed 与签名/凭据事实不一致",
                key in secretTypes,
                Capability.SECRET_USED in caps(d),
            )
        }
        // 应用通道的 secret 就是 corpsecret / app_secret：必填凭据，恒为 true
        for (d in all.filter { it["family"] == "app" }) {
            assertTrue("${d["key"]} 必须声明 secretUsed", Capability.SECRET_USED in caps(d))
        }
    }

    @Test
    fun customTemplateMatchesTemplateStrategy() {
        for (spec in ChannelRegistry.CHANNELS) {
            val d = ChannelRegistry.descriptorOf(spec.type)
            assertEquals(
                "${spec.type} 的 customTemplate 与模板策略不一致",
                spec.transport.templateSupport != TemplateSupport.DISABLED,
                Capability.CUSTOM_TEMPLATE in caps(d),
            )
            assertEquals(
                "${spec.type} 的 rawTemplateBody 只应是 RAW_BODY",
                spec.transport.templateSupport == TemplateSupport.RAW_BODY,
                Capability.RAW_TEMPLATE_BODY in caps(d),
            )
        }
    }

    @Test
    fun appChannelFieldsAreExportedWithLabelsAndDefaults() {
        // 应用通道的表单完全由这份 schema 渲染：漏一个字段 = 用户没地方填
        val wecom = AppChannelRegistry.spec(AppChannelTypes.WECOM_APP)!!.descriptor()
        assertEquals(
            listOf("corpid", "agentid", "touser"),
            (wecom["fields"] as List<Map<String, Any?>>).map { it["key"] },
        )
        val agentid = (wecom["fields"] as List<Map<String, Any?>>).first { it["key"] == "agentid" }
        assertEquals("number", agentid["kind"])
        assertEquals("0", agentid["defaultValue"])
        assertEquals(true, agentid["required"])

        val feishu = AppChannelRegistry.spec(AppChannelTypes.FEISHU_APP)!!.descriptor()
        assertEquals(
            listOf("app_id", "receive_id_type", "receive_id"),
            (feishu["fields"] as List<Map<String, Any?>>).map { it["key"] },
        )
        // 官方基址导出给 Dart：新增通道时 Dart 不再抄一份 URL 字面量
        assertEquals(AppChannelTypes.WECOM_OFFICIAL_BASE, wecom["officialBase"])
        assertEquals(AppChannelTypes.FEISHU_OFFICIAL_BASE, feishu["officialBase"])
    }

    // ── 4. 导出快照 == Dart 侧 fixture ──────────────────────────────────

    private fun toJsonValue(value: Any?): Any = when (value) {
        null -> JSONObject.NULL
        is List<*> -> JSONArray().apply { value.forEach { put(toJsonValue(it)) } }
        is Map<*, *> -> JSONObject().apply {
            value.forEach { (k, v) -> put(k as String, toJsonValue(v)) }
        }
        else -> value
    }

    @Test
    fun dartFixtureMatchesProductionExport() {
        // 快照直接由**生产载荷**渲染（T08-B）：以前这里自己 mapOf 一遍，
        // handler 少发一个键也照样绿，Dart 只表现为"档位莫名少一排"。
        val root = JSONObject()
        channelDescriptorsPayload().forEach { (k, v) -> root.put(k, toJsonValue(v)) }
        val rendered = root.toString(2) + "\n"
        if (!fixtureFile.exists()) {
            fixtureFile.writeText(rendered, Charsets.UTF_8)
            fail(
                "描述符快照不存在，已生成 ${fixtureFile.path}；" +
                    "请人工核对内容（尤其 capabilities 与 fields）后重跑。",
            )
        }
        // 只比内容不比换行符：本机 core.autocrlf=true，签出后 fixture 会是 CRLF，
        // 而 rendered 永远是 "\n"，逐字节比会让这条守卫在干净签出下恒红。
        val committed = fixtureFile.readText(Charsets.UTF_8).replace("\r\n", "\n")
        assertEquals(
            "描述符导出变了：Dart widget 测试的 fixture 会跟着失真。" +
                "确认改动是有意的之后删除本文件重跑生成，并同步 base.md。",
            committed,
            rendered,
        )
    }
}
