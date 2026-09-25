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
 * "类型列表少一项"，而不是编译错误。本类锁五件事：
 * 1. 载荷必须是 MethodChannel standard codec 能过的类型（放 enum / JSONObject 进去
 *    会在运行时抛 IllegalArgumentException，而且只在点开设置页时抛）；
 * 2. key 全局唯一、family 只能是 webhook / app / email（Dart 按 family 分页渲染）；
 * 3. 能力位必须由描述符事实派生，不能有人另抄一份名单（`secretUsed` 与签名表、
 *    `customTemplate` 与模板策略两两核对）；
 * 4. **邮件族**（T08-C）：描述符声明的列 == `EmailManager` 真读的列，且预置档位不带正文
 *    （正文留 ARB，否则英文界面点档位会把中文写进用户配置）；
 * 5. **导出快照** `channel_descriptors.json` 与生产代码逐字节一致（快照由**生产构造点**
 *    `channelDescriptorsPayload()` 渲染）—— 该文件同时是 Dart widget 测试的 fixture，
 *    所以它必须来自原生表本身，否则测试是在对着一份手抄的假描述符跑绿。
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
        get() = ChannelRegistry.descriptors() +
            AppChannelRegistry.descriptors() +
            EmailChannelSpec.descriptors()

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
            "webhook 12 + 应用通道 2 + 邮件 1",
            mapOf("webhook" to 12, "app" to 2, "email" to 1),
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

    // ── 4. 邮件族：表 ⇄ 原生真读的列 ────────────────────────────────────

    /** 读一个主源码文件并剥注释（守卫用的都是可执行代码里的字面量）。 */
    private fun mainSource(name: String): String = stripComments(
        File(
            repoRoot,
            "android/app/src/main/kotlin/com/fnthink/notice/$name",
        ).readText(Charsets.UTF_8),
    )

    @Suppress("UNCHECKED_CAST")
    @Test
    fun emailFieldsMatchWhatNativeActuallyReads() {
        // 反证过方向的两种坏法：表里多一个键 = 用户在界面上填了但发送时没人读
        // （`extra_config` 就是这条死链路活了三个版本）；表里少一个键 = 发送侧读空值，
        // 表现是"配了却发不出去"。
        val declared = EmailChannelSpec.fields.map { it.key }.toSet()
        val read = Regex("""obj\.opt(?:String|Int|Boolean|Long)\("([A-Za-z][A-Za-z0-9_]*)""")
            .findAll(mainSource("EmailManager.kt"))
            .map { it.groupValues[1] }
            .toSet()
        // 这三列由列表页与路由管（启停、主备角色、身份），不进表单 schema
        val notFormFields = setOf("id", "enabled", "role")
        // password 是**例外**：它不在 obj 列里，而在原生按 id 键控的加密表（下面单独钉），
        // 所以不能混在同一次集合比对里 —— 混了就会把"表里有 password"判成假违规。
        assertEquals(
            "邮件描述符字段与 `EmailManager` 真读的列不一致（差集见左右两边）",
            read - notFormFields,
            declared - setOf("password"),
        )
        // 密码走原生按 id 键控的加密表，必须仍然在表里（它不是 obj 列，故单独钉）
        assertTrue("'password' 不在描述符里：表单没地方填授权码", "password" in declared)
        assertTrue(
            "原生仍在按 id 读密码表，描述符却声明了 password ⇒ 两侧存储形状要重新对齐",
            mainSource("EmailManager.kt").contains("passwords[id]"),
        )
        // 默认值也只能有一处：表说 465、原生兜底写另一个数，表现是"没填过的通道"
        // 在界面上显示 A、发信时按 B 连（T08-C 之前端口在六处各写一遍）。
        @Suppress("UNCHECKED_CAST")
        val declaredFields = EmailChannelSpec.descriptor()["fields"] as List<Map<String, Any?>>
        assertEquals(
            "smtpPort 的表内默认值必须就是常量本身",
            EmailChannelSpec.DEFAULT_PORT.toString(),
            declaredFields.first { it["key"] == "smtpPort" }["defaultValue"],
        )
        val manager = mainSource("EmailManager.kt")
        assertTrue(
            "EmailManager 又写了自己的端口字面量（应引用 EmailChannelSpec.DEFAULT_PORT）",
            manager.contains("optInt(\"smtpPort\", EmailChannelSpec.DEFAULT_PORT)"),
        )
        assertTrue(
            "EmailManager 又写了自己的 SSL 兜底字面量",
            manager.contains("optBoolean(\"useSSL\", EmailChannelSpec.DEFAULT_USE_SSL)"),
        )
    }

    @Suppress("UNCHECKED_CAST")
    @Test
    fun emailPresetsCarryNoTemplateText() {
        // 预置档位的正文必须留 ARB：写在原生 = 第二份文案（而且只有一种语言，
        // 英文界面点档位会往用户配置里塞中文 —— 这就是这次要修掉的缺陷）。
        val descriptor = EmailChannelSpec.descriptor()
        val fields = descriptor["fields"] as List<Map<String, Any?>>
        val presetBearing = fields.filter {
            (it["presets"] as List<Map<String, Any?>>).isNotEmpty()
        }
        assertEquals(
            "只有模板类字段可以有预置档位",
            listOf("subjectTemplate", "bodyTemplate"),
            presetBearing.map { it["key"] },
        )
        for (f in presetBearing) {
            val presets = f["presets"] as List<Map<String, Any?>>
            assertTrue("${f["key"]} 一个档位都没有：界面会给一排空按钮", presets.isNotEmpty())
            for (t in presets) {
                assertTrue(
                    "${f["key"]} 的档位缺 labelKey",
                    (t["labelKey"] as? String)?.isNotEmpty() == true,
                )
                val valueKey = t["valueKey"] as? String
                // valueKey=null 是显式语义：清空该字段 = 用运行时默认（邮件正文的「默认」档位）
                assertTrue(
                    "${f["key"]} 的档位 valueKey 必须是 emailPreset* 资源名或 null（=清空）",
                    valueKey == null || valueKey.startsWith("emailPreset"),
                )
            }
        }
    }

    // ── 5. 导出快照 == Dart 侧 fixture ──────────────────────────────────

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
