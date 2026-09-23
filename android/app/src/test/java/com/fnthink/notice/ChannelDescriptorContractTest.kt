package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 「新增一个通道只填描述符」的机器判据（第 4 步）。
 *
 * 本步把过去 4 类**强制改动点**收进了 [ChannelRegistry]：
 * 1. 签名方式（`WebhookSigner` 的 12 臂 `when`）→ [ChannelSpec.signature]
 * 2. 存储值解析（`ConfigManager.parseWebhookType` 的 12 臂 + 数字表）→ [ChannelSpec.storedTokens]
 * 3. 发送层事实（`WebhookSender` 的 5 个 `if (cfg.type == ...)` 早退分支）→ [ChannelSpec.transport]
 * 4. 正文上限（Telegram/Discord/企微应用各自内联的魔数）→ [ChannelTransport.textLimitChars]
 *
 * 于是"改动点消失"必须可验证，否则下一个改动就会把 `when` 加回来而没人发现。
 * 本类的源码守卫就是干这个的：**除描述符表与枚举定义外，生产代码不得再出现平台枚举的分支**。
 */
class ChannelDescriptorContractTest {

    private val specs = ChannelRegistry.CHANNELS

    private fun repoFile(rel: String): File {
        // JVM 测试的工作目录是 android/app（Gradle 模块根），向上找到仓库根
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

    private fun sourceOf(rel: String): String =
        stripComments(repoFile("app/src/main/kotlin/com/fnthink/notice/$rel").readText())

    // ── 表本身完整、无重复 ────────────────────────────────────────────────

    @Test
    fun everyEnumValueHasExactlyOneSpec() {
        val types = specs.map { it.type }
        assertEquals("枚举值与表项必须 1:1", WebhookPayloadBuilder.WebhookType.values().toSet(), types.toSet())
        assertEquals("不得有重复表项", types.size, types.toSet().size)
    }

    @Test
    fun storedTokensAreGloballyUnique() {
        val seen = HashMap<String, WebhookPayloadBuilder.WebhookType>()
        for (spec in specs) {
            for (token in spec.storedTokens) {
                val key = token.lowercase()
                val previous = seen[key]
                assertNull("$key 同时属于 $previous 和 ${spec.type}：存储值歧义会让通道被判错", previous)
                seen[key] = spec.type
            }
        }
    }

    @Test
    fun legacyDigits_coverTheHistoricalZeroToElevenRange() {
        // 早期把类型按 "0".."11" 存进 DB（**不是**枚举下标：3=generic、4=telegram）。
        // 少一个数字，那条历史记录就会被读成 GENERIC，表现为"能推但状态/格式全错"。
        val digits = specs.flatMap { s -> s.legacyTokens.filter { it.all { c -> c.isDigit() } } }
        assertEquals("数字别名应为 0..11 共 12 个", (0..11).map { it.toString() }.toSet(), digits.toSet())
    }

    // ── 存储值解析：旧 ConfigManager 的 12 臂 when 的行为必须逐条保留 ──────

    @Test
    fun typeByStoredToken_resolvesEveryHistoricalSpelling() {
        val expected = mapOf(
            "wechat_work" to WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
            "wechatwork" to WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
            "WECHAT_WORK" to WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
            "0" to WebhookPayloadBuilder.WebhookType.WECHAT_WORK,
            "dingtalk" to WebhookPayloadBuilder.WebhookType.DINGTALK,
            "1" to WebhookPayloadBuilder.WebhookType.DINGTALK,
            "feishu" to WebhookPayloadBuilder.WebhookType.FEISHU,
            "2" to WebhookPayloadBuilder.WebhookType.FEISHU,
            "generic" to WebhookPayloadBuilder.WebhookType.GENERIC,
            "3" to WebhookPayloadBuilder.WebhookType.GENERIC,
            "telegram" to WebhookPayloadBuilder.WebhookType.TELEGRAM,
            "4" to WebhookPayloadBuilder.WebhookType.TELEGRAM,
            "bark" to WebhookPayloadBuilder.WebhookType.BARK,
            "5" to WebhookPayloadBuilder.WebhookType.BARK,
            "server_chan" to WebhookPayloadBuilder.WebhookType.SERVER_CHAN,
            "serverchan" to WebhookPayloadBuilder.WebhookType.SERVER_CHAN,
            "6" to WebhookPayloadBuilder.WebhookType.SERVER_CHAN,
            "push_plus" to WebhookPayloadBuilder.WebhookType.PUSH_PLUS,
            "pushplus" to WebhookPayloadBuilder.WebhookType.PUSH_PLUS,
            "7" to WebhookPayloadBuilder.WebhookType.PUSH_PLUS,
            "ntfy" to WebhookPayloadBuilder.WebhookType.NTFY,
            "8" to WebhookPayloadBuilder.WebhookType.NTFY,
            "gotify" to WebhookPayloadBuilder.WebhookType.GOTIFY,
            "9" to WebhookPayloadBuilder.WebhookType.GOTIFY,
            "slack" to WebhookPayloadBuilder.WebhookType.SLACK,
            "10" to WebhookPayloadBuilder.WebhookType.SLACK,
            "discord" to WebhookPayloadBuilder.WebhookType.DISCORD,
            "11" to WebhookPayloadBuilder.WebhookType.DISCORD,
        )
        val urlless = "https://unknown-host.example.com/hook"
        expected.forEach { (stored, type) ->
            assertEquals("存储值 $stored 解析错了", type, ChannelRegistry.typeByStoredToken(stored))
            // 大小写与空白不得影响结果（DB 里存过混合写法）
            assertEquals("存储值 $stored 对大小写/空白敏感", type, ChannelRegistry.typeByStoredToken("  $stored  "))
        }
        // 未知值必须交给 host 兜底，而不是在这里发明默认值
        assertNull(ChannelRegistry.typeByStoredToken(""))
        assertNull(ChannelRegistry.typeByStoredToken("weird_new_type"))
        assertNull(ChannelRegistry.typeByStoredToken("12"))
        assertEquals(
            WebhookPayloadBuilder.WebhookType.FEISHU,
            ChannelRegistry.typeByStoredToken("FEISHU") ?: WebhookPayloadBuilder.detectType(urlless)
        )
    }

    // ── 声明与实现同源：正文上限 ──────────────────────────────────────────

    @Test
    fun declaredTextLimits_matchTheTruncatorsBehaviour() {
        // ⚠ 这里必须写**平台文档里的字面数字**，不能写 ChannelLimits.XXX：
        //    用常量的话"改常量"会同时改断言两侧，测试恒绿（第一版就踩到了，
        //    植入 1999 后 golden 与断言都不红——快照输入很短，根本走不到截断）。
        val tg = ChannelRegistry.spec(WebhookPayloadBuilder.WebhookType.TELEGRAM).transport
        assertEquals("Telegram sendMessage 文本上限是 4096 字符", 4096, tg.textLimitChars)
        val longText = "a".repeat(5000)
        val text = org.json.JSONObject(WebhookPayloadBuilder.buildTelegramMessage(longText, "1"))
            .getString("text")
        assertEquals("声明 4096 但实发正文没截到 4096", 4096, text.length)

        val dc = ChannelRegistry.spec(WebhookPayloadBuilder.WebhookType.DISCORD).transport
        assertEquals("Discord content 上限是 2000 字符", 2000, dc.textLimitChars)
        assertEquals(
            "声明 2000 但 truncateForDiscord 没按 2000 截",
            2000,
            WebhookPayloadBuilder.truncateForDiscord("b".repeat(3007)).length,
        )
    }

    @Test
    fun truncator_neverSplitsSurrogatePair_atTheBoundary() {
        // 上限位正好落在代理项对中间时必须回退一位，否则发出的是非法字符（平台 400）
        val emoji = "😀" // 一个代理项对
        val text = "a".repeat(ChannelLimits.DISCORD_CHARS - 1) + emoji + "tail"
        val out = ChannelDefaults.truncateChars(text, ChannelLimits.DISCORD_CHARS)
        assertTrue("截断结果把代理项对拆开了", !Character.isHighSurrogate(out[out.length - 1]))
        assertEquals(ChannelLimits.DISCORD_CHARS - 1, out.length)
    }

    @Test
    fun appChannelLimits_useTheSameSingleSourceConstants() {
        val wecom = AppChannelRegistry.spec(AppChannelTypes.WECOM_APP)!!
        val feishu = AppChannelRegistry.spec(AppChannelTypes.FEISHU_APP)!!
        val cjk = "中".repeat(3000) // 每字 3 字节
        assertEquals(
            "企微应用正文上限不再是 ChannelLimits 常量",
            ChannelLimits.WECOM_APP_BYTES / 3,
            wecom.truncate(cjk).length,
        )
        assertEquals(
            "飞书应用正文上限不再是 ChannelLimits 常量",
            ChannelLimits.FEISHU_APP_CHARS,
            feishu.truncate("x".repeat(4000)).length,
        )
    }

    // ── 模板策略：把"事实上不生效"变成可见声明，并防止有人悄悄改回去 ───────

    @Test
    fun templateSupport_matchesWhoActuallyHonoursCustomTemplates() {
        // 重构前这 4 个平台在模板代码之前就 return 了，用户选的格式/模板对它们不生效
        for (t in listOf(
            WebhookPayloadBuilder.WebhookType.NTFY,
            WebhookPayloadBuilder.WebhookType.GOTIFY,
            WebhookPayloadBuilder.WebhookType.SERVER_CHAN,
            WebhookPayloadBuilder.WebhookType.PUSH_PLUS,
        )) {
            assertEquals("$t 的模板策略必须仍是 DISABLED", TemplateSupport.DISABLED, ChannelRegistry.spec(t).transport.templateSupport)
        }
        // Slack / Discord 第 5 步补上：它们不在旧的回退分支里，而是**从未登记** platformPayload，
        // 所以 buildPlatformPayload 恒返回 null —— 同样是「选了没效果」，UI 入口一并收掉。
        // 判据只有一条：有 platformPayload 才可能有 customTemplate，见下面的双向核对。
        for (t in listOf(
            WebhookPayloadBuilder.WebhookType.SLACK,
            WebhookPayloadBuilder.WebhookType.DISCORD,
        )) {
            assertEquals("$t 无 platformPayload，模板策略必须是 DISABLED", TemplateSupport.DISABLED, ChannelRegistry.spec(t).transport.templateSupport)
        }
        // 通用 webhook 的自定义模板是"原样发出渲染结果"
        assertEquals(TemplateSupport.RAW_BODY, ChannelRegistry.spec(WebhookPayloadBuilder.WebhookType.GENERIC).transport.templateSupport)
        // 其余平台走平台包装（企微/钉钉/飞书的 text/markdown）
        assertEquals(TemplateSupport.STANDARD, ChannelRegistry.spec(WebhookPayloadBuilder.WebhookType.WECHAT_WORK).transport.templateSupport)
    }

    @Test
    fun customTemplateCapability_neverAdvertisesADeadSelector() {
        // 第 5 步起 UI 的「消息格式 / 模板」入口按 CUSTOM_TEMPLATE 能力位显隐，
        // 所以这条声明必须与实发路径严格等价，否则要么给出死选择器、要么藏掉有效功能。
        // STANDARD ⇒ 必须有 platformPayload（buildPlatformPayload 里没有它就拿不到正文）；
        // RAW_BODY ⇒ 走 buildGenericBody，是通用 webhook 专用。
        for (spec in specs) {
            when (spec.transport.templateSupport) {
                TemplateSupport.DISABLED -> Unit
                TemplateSupport.STANDARD -> assertNotNull(
                    "${spec.type} 标了 STANDARD 却没有 platformPayload：格式/模板选择器对它不生效，应改成 DISABLED",
                    spec.platformPayload,
                )
                TemplateSupport.RAW_BODY -> assertEquals(
                    "RAW_BODY 只有通用 webhook 一条路径",
                    WebhookPayloadBuilder.WebhookType.GENERIC,
                    spec.type,
                )
            }
        }
        // 能力位与之一致（导给 Dart 的就是这个）
        for (t in listOf(
            WebhookPayloadBuilder.WebhookType.NTFY,
            WebhookPayloadBuilder.WebhookType.GOTIFY,
            WebhookPayloadBuilder.WebhookType.SERVER_CHAN,
            WebhookPayloadBuilder.WebhookType.PUSH_PLUS,
            WebhookPayloadBuilder.WebhookType.SLACK,
            WebhookPayloadBuilder.WebhookType.DISCORD,
        )) {
            assertFalse(
                "$t 不该声明 customTemplate",
                ChannelRegistry.capabilitiesOf(t).contains(Capability.CUSTOM_TEMPLATE),
            )
        }
    }

    @Test
    fun bodyOverride_declaresWhereRealBodyDiffersFromNotify() {
        // 有覆写 = 「实发正文 ≠ notify 产出」，快照会用 body|<TYPE> 单独锁，见 ChannelBehaviorGoldenTest
        val overridden = specs.filter { it.transport.bodyOverride != null }.map { it.type }
        assertEquals(
            "实发正文与 notify 不一致的通道只有这两个（新增时必须同步快照与文档）",
            setOf(
                WebhookPayloadBuilder.WebhookType.SERVER_CHAN,
                WebhookPayloadBuilder.WebhookType.PUSH_PLUS,
            ),
            overridden.toSet(),
        )
    }

    // ── 源码守卫：强制改动点不得长回来 ────────────────────────────────────

    @Test
    fun productionCodeMustNotBranchOnWebhookTypeAgain() {
        val files = listOf(
            "WebhookSender.kt",
            "WebhookSigner.kt",
            "ConfigManager.kt",
            "NetworkClient.kt",
            "WebhookResponseParser.kt",
            "TemplateEngine.kt",
        )
        val enumRef = Regex("WebhookType\\.(WECHAT_WORK|DINGTALK|FEISHU|TELEGRAM|BARK|SERVER_CHAN|PUSH_PLUS|NTFY|GOTIFY|SLACK|DISCORD)")
        for (rel in files) {
            val src = sourceOf(rel)
            val hits = enumRef.findAll(src).map { it.value }.toSet()
            assertTrue(
                "$rel 又出现按平台分支 $hits —— 这些事实必须写进 ChannelRegistry 的描述符",
                hits.isEmpty()
            )
        }
    }

    @Test
    fun signerAndConfigManagerNoLongerOwnTheirOwnTables() {
        // 签名器里不该再有平台名；存储值解析里不该再有数字字面量表
        val signer = sourceOf("WebhookSigner.kt")
        assertTrue("WebhookSigner 又出现 signWechatWork 之类的按平台函数", !signer.contains("signWechatWork"))
        assertTrue(signer.contains("SignatureScheme."))
        val cfg = sourceOf("ConfigManager.kt")
        assertTrue(
            "ConfigManager 又自己维护了一份 channel_type 映射表",
            !Regex("\"(wechat_work|dingtalk|feishu)\"").containsMatchIn(cfg)
        )
        assertTrue(cfg.contains("ChannelRegistry.typeByStoredToken"))
    }

    // ── 合成新通道：证明"只填描述符"在原生侧成立（SOP 情形 A） ─────────────

    @Test
    fun aBrandNewChannel_needsNothingButADescriptor() {
        // 不新增枚举、不改签名器、不改发送层：只造一个描述符，然后走同一批通用实现
        val synthetic = ChannelSpec(
            type = WebhookPayloadBuilder.WebhookType.GENERIC, // 借位用：合成通道不注册进全局表
            hosts = listOf("mattermost.example.com"),
            legacyTokens = listOf("99"),
            signature = SignatureScheme.URL_TIMESTAMP_MILLIS,
            transport = ChannelTransport(
                contentType = "application/json; charset=utf-8",
                requiredUrlParam = UrlParam.CHAT_ID,
                missingParamReason = "缺少 chat 参数",
                textLimitChars = ChannelLimits.DISCORD_CHARS,
            ),
            notify = { p -> """{"text":"${p.title}"}""" },
            test = { p -> """{"text":"test ${p.deviceName}"}""" },
            sms = { _ -> """{"text":"sms"}""" },
            call = { _ -> """{"text":"call"}""" },
            parse = null,
        )

        // 1) 存储值/别名：新通道的写法不需要改任何 when 就能解析
        // 查找侧大小写无关 ⇒ storedTokens 按 lowercase 去重，所以别名比 lowercase 集合
        val aliases = synthetic.storedTokens.map { it.lowercase() }.toSet()
        assertTrue("别名缺早期数字 99：$aliases", aliases.contains("99"))
        assertTrue("别名缺自动派生的枚举名：$aliases", aliases.contains("generic"))
        assertEquals(
            "大小写别名必须收敛成一条",
            synthetic.storedTokens.size,
            aliases.size,
        )

        // 2) 发送决策：完全由描述符驱动（不查全局表、不碰网络）
        val plan = ChannelDispatch.plan(
            synthetic,
            OutboundInput(
                url = "https://mattermost.example.com/hook?i=K7",
                secret = "s3cret",
                chatId = "channel-1",
                urlToken = "",
                overrideBody = { null },
                platformBody = { null },
                rawTemplateBody = { null },
                defaultBody = { "{\"text\":\"x\"}" }
            )
        )
        assertNull("缺 chat_id 必须提前失败", plan.earlyFailReason)

        // 3) 缺必填参数 → 早失败原因来自声明（发送层不认识任何平台名）
        val blocked = ChannelDispatch.plan(
            synthetic,
            OutboundInput(
                url = "https://mattermost.example.com/hook",
                secret = "s3cret",
                chatId = "",
                urlToken = "",
                overrideBody = { null },
                platformBody = { null },
                rawTemplateBody = { null },
                defaultBody = { "{\"text\":\"x\"}" }
            )
        )
        assertEquals("缺少 chat 参数", blocked.earlyFailReason)

        // 4) 签名：通用实现按声明的方案工作（timestamp 固定 ⇒ 可逐字节断言）
        val signed = WebhookSigner.signBy(
            synthetic.signature,
            synthetic.type,
            plan.url,
            plan.body,
            plan.secretForSigner,
            1700000000123L
        )
        assertTrue("新通道没拿到 timestamp：${signed.url}", signed.url.contains("&timestamp=1700000000123&sign="))
        assertTrue("新通道的 secret 必须交给签名层", plan.secretForSigner != null)

        // 5) 判定：非 JSON 的 200 响应按声明的契约处理（默认 true = 业务码才算数）
        val verdict = WebhookResponseParser.parseBySpec(
            synthetic,
            synthetic.type,
            200,
            "<html>proxy login required</html>"
        )
        assertEquals(
            "声明了 JSON 契约却被当成送达成功 = 假成功 + 静默丢内容",
            WebhookResponseParser.DeliveryStatus.BIZ_FAIL,
            verdict.status
        )

        // 6) 截断：声明的上限由通用实现执行
        assertEquals(
            ChannelLimits.DISCORD_CHARS,
            ChannelDefaults.truncateChars("c".repeat(3000), synthetic.transport.textLimitChars!!).length,
        )
    }

    // ── 跨语言身份口径：slug / labelKey ──────────────────────────────────

    @Test
    fun slug_isTheSameIdentityDartUsesInDeliveryKeys() {
        // Dart 的送达键是 chan:<slug>（channel_delivery_keys_test 锁 Dart 侧）；
        // 这里锁原生侧的 slug 口径：小写 snake_case、全局唯一、且与 Dart 的别名表同源。
        val slugs = specs.map { it.slug }
        assertEquals("slug 必须唯一", slugs.toSet().size, slugs.size)
        for (spec in specs) {
            assertTrue(
                "slug 必须是小写 snake_case：${spec.slug}",
                Regex("^[a-z][a-z0-9_]*$").matches(spec.slug)
            )
            assertEquals(
                "slug 必须由枚举名派生（否则两端各推一套）",
                spec.type.name.lowercase(),
                spec.slug
            )
        }
    }

    @Test
    fun labelKeys_existInArb() {
        // 只存资源名、译文只在 ARB —— 但资源名写错就是运行时缺词条，所以跨语言锁一遍
        val arb = ioReader(repoFile("lib/l10n/arb/app_zh.arb"))
        for (spec in specs) {
            assertTrue(
                "${spec.slug} 的 labelKey=${spec.labelKey} 不在 app_zh.arb 里",
                arb.contains("\"${spec.labelKey}\"")
            )
        }
    }

    @Test
    fun requiresJsonContract_isDeclaredExplicitly() {
        // 200 + 非 JSON body 是否算成功。false 的只有 5 家，且必须逐名点出来：
        // 少一家 = 自建端点的 200 "OK" 被误判失败（大面积误报）；
        // 多一家 = 反代/门户回的 200 + HTML 被当成送达（假成功、静默丢内容）。
        val noJsonContract = specs.filter { !it.requiresJsonContract }.map { it.type.name }.toSet()
        assertEquals(
            setOf("GENERIC", "NTFY", "GOTIFY", "SLACK", "DISCORD"),
            noJsonContract
        )
        assertEquals(
            "其余 7 家都按业务码判定",
            7,
            specs.count { it.requiresJsonContract }
        )
    }

    private fun ioReader(f: java.io.File): String = f.readText(Charsets.UTF_8)
}
