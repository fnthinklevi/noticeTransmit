package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * T133 片4：手动补推的**范围**（重推只发"这一条里可再发的那几族"）。
 *
 * ## 报上来的形状
 * 历史记录那条「现在推送」把**全部启用通道**重发一遍：一条只有钉钉失败、企业微信成功的通知，
 * 点一下企业微信会再收到同一条内容 —— 收件端多出的是重复消息，不是补发。
 *
 * ## 这一发要同时成立的四件事（各钉一组）
 * 1. [RepushScope.accepts] 的三档语义：`null` = 不限定、**空集合 = 谁都不发**、非空 = 按 slug 放行
 *    （空集被折成 null 就是回到"全部重发"，而且不报错）；
 * 2. 范围沿 ACTION_PUSH_RECORD_NOW → pushRecordNow → dispatchToChannels → routeChannels 一路带到底，
 *    断一环那一环之后所有人都收到"不限定"；
 * 3. 四族**都**要在扇出口过范围 —— 漏一族的表现就是"重推邮件那一族，却把钉钉也发一遍"；
 * 4. 范围**不改变主备裁决的输入**：先路由（全部候选）后收窄（这一发给谁），
 *    否则会出现"按族筛候选 ⇒ 主通道被自己筛没 ⇒ 判成降级"这套第二份路由。
 *
 * ⚠ 本文件一半是纯函数用例，一半是**静态源码断言**（读 .kt 源文本，不启动 Android 运行时）。
 *   仓库根用 `../..` / `..` / `.` 逐个探测，不猜路径。
 */
class RepushScopeTest {

    private val root: String = run {
        val candidates = listOf("../..", "..", ".")
        candidates.firstOrNull { rel ->
            File("$rel/android/app/src/main/kotlin/com/fnthink/notice/RepushScope.kt").exists()
        } ?: throw IllegalStateException("未找到仓库根目录")
    }

    private fun src(rel: String): String =
        stripComments(File("$root/$rel").readText())

    private val service =
        src("android/app/src/main/kotlin/com/fnthink/notice/NotificationMonitorService.kt")
    private val mainActivity =
        src("android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt")

    // ── 1. 三档语义 ────────────────────────────────────────────────────────

    @Test
    fun nullMeansUnbounded() {
        assertTrue(RepushScope.accepts(null, "dingtalk"))
        assertTrue(RepushScope.accepts(null, "email"))
    }

    @Test
    fun emptySetSendsNothing_notEverything() {
        // 这一条是片4 的全部风险所在：空集折成"不限定"不会崩、不会报错，只会多发一遍。
        assertFalse(
            "空范围必须读成「谁都不发」。读成不限定 = 回到本片要修的那句「重置全部启用通道」",
            RepushScope.accepts(emptyList(), "dingtalk"),
        )
        assertFalse(RepushScope.accepts(listOf<String>(), "email"))
    }

    @Test
    fun nonEmptyLetsOnlyListedSlugsThrough() {
        val scope = listOf("dingtalk")
        assertTrue(RepushScope.accepts(scope, "dingtalk"))
        assertFalse(
            "范围外的族不许被捎带发出去 —— 收件端那一条已经送达了",
            RepushScope.accepts(scope, "wechat_work"),
        )
    }

    @Test
    fun matchingIsCaseAndSpaceTolerant() {
        // Dart 递的是 slug，原生比对的是 `ChannelSpec.slug` / `cfg.type`；两侧的大小写写法
        // 历史上就不齐（回传侧还有 "EMAIL" 这种枚举名）。归一在接缝上做一次性，别指望上游都小写。
        assertTrue(RepushScope.accepts(listOf(" DINGTALK "), "dingtalk"))
        assertTrue(RepushScope.accepts(listOf("email"), " EMAIL "))
    }

    // ── 2. 范围一路带到底（静态形状） ──────────────────────────────────────

    @Test
    fun scopeReachesTheFanout_notDroppedAlongTheWay() {
        // intent → 服务：读的是**同一个常量**，不是再抄一遍字面量
        assertTrue(
            "onStartCommand 没从 intent 里取范围 ⇒ 参数在 intent 之后就断了",
            service.contains("getStringArrayListExtra(EXTRA_REPUSH_SLUGS)"),
        )
        assertTrue(
            "MainActivity 那一侧必须写同一个常量（第二份键名会各自漂开）",
            mainActivity.contains("EXTRA_REPUSH_SLUGS"),
        )
        // 服务内部：ACTION → pushRecordNow → dispatchToChannels 三环都要把范围递下去
        assertTrue(
            "手动补推没把范围交给扇出收口",
            methodBody(service, "private fun pushRecordNow(").contains("onlySlugs = onlySlugs"),
        )
        assertTrue(
            "收口函数没把范围转给路由 ⇒ 四族照旧全发",
            methodBody(service, "private fun dispatchToChannels(")
                .contains("routeChannels(onlySlugs)"),
        )
    }

    @Test
    fun extraKeyHasExactlyOneDefinition() {
        val hits = Regex(""""repush_slugs"""").findAll(service).count()
        assertEquals(
            "intent extra 的键名只许在常量定义处出现一次（别处一律引用常量）",
            1,
            hits,
        )
    }

    // ── 3. 四族都在扇出口过范围 ────────────────────────────────────────────

    @Test
    fun allFourFamiliesAreScopeFiltered() {
        val body = methodBody(service, "private fun routeChannels(")
        for (family in listOf("webhooks", "apps", "emails", "fnthinks")) {
            val start = body.indexOf("$family.filter")
            assertTrue("路由结果里找不到 $family 这一族（新增一族却没过范围）", start >= 0)
            val end = body.indexOf("},", start)
            val arm = body.substring(start, if (end > start) end else body.length)
            assertTrue(
                "$family 这一族没按范围收窄 ⇒ 重推别的族时会把它一起发出去",
                arm.contains("inScope"),
            )
        }
    }

    @Test
    fun emailAndFnthinkSlugs_matchWhatTheNotifierReports() {
        // 这两族各只有一种 slug，而且是**字面量**。它们必须与"送达结果回传给 Dart 的那个串"同源，
        // 否则 Dart 按 `chan:email` 算出范围、原生按另一个串过滤 ⇒ 一格都对不上。
        val routeBody = methodBody(service, "private fun routeChannels(")
        val reportPattern = Regex("""DeliveryNotifier\.notify\(this, info\.id, "([^"]+)"""")

        val email = reportPattern.find(methodBody(service, "private fun dispatchEmail("))
        assertTrue("没从 dispatchEmail 里现取到回传类型串（写法变了，本用例要跟着改）", email != null)
        val emailSlug = email!!.groupValues[1].lowercase()
        assertTrue(
            "dispatchEmail 回传的是 $emailSlug，扇出口却按别的串过滤邮件族",
            routeBody.contains("""inScope("$emailSlug")"""),
        )

        val fn = reportPattern.find(methodBody(service, "private fun dispatchFnthinkHook("))
        assertTrue("没从 dispatchFnthinkHook 里现取到回传类型串", fn != null)
        val fnthinkSlug = fn!!.groupValues[1].lowercase()
        assertTrue(
            "dispatchFnthinkHook 回传的是 $fnthinkSlug，扇出口却按别的串过滤幻念族",
            routeBody.contains("""inScope("$fnthinkSlug")"""),
        )
    }

    // ── 4. 范围不参与主备裁决 ──────────────────────────────────────────────

    @Test
    fun scopeNarrowsAfterRouting_notBefore() {
        val body = methodBody(service, "private fun routeChannels(")
        val route = body.indexOf("ChannelRouting.route(")
        val firstScope = body.indexOf("inScope")
        assertTrue("找不到路由裁决那一发（写法变了，本用例要跟着改）", route >= 0)
        assertTrue("找不到范围过滤（说明范围根本没落到扇出口）", firstScope >= 0)
        assertTrue(
            "范围必须在裁决**之后**收窄：先按族筛候选，主通道会被自己筛没，" +
                "于是 ChannelRouting 判成「主通道全不可用」→ 降级 —— 那是第二套路由",
            route < firstScope,
        )
        assertFalse(
            "构造候选集时就判了范围（那是把裁决的输入改窄）",
            Regex("""members\.add\(.*inScope""").containsMatchIn(body),
        )
    }

    // ── helper ─────────────────────────────────────────────────────────────

    /** 剥块注释与行注释（源码守卫不剥注释，注释里的字面量会被当成真代码命中）。 */
    private fun stripComments(text: String): String =
        text
            .replace(Regex("(?s)/\\*.*?\\*/"), "")
            .lines()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    /** 取一个方法体：从签名到配对结束的 `}`（与仓库里各 Kotlin 源码守卫同一口径）。 */
    private fun methodBody(source: String, signature: String): String {
        val start = source.indexOf(signature)
        assertTrue("未找到函数签名：$signature", start >= 0)
        val braceStart = source.indexOf('{', start)
        assertTrue("签名后没有函数体：$signature", braceStart >= 0)
        var depth = 0
        var i = braceStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return source.substring(braceStart, i + 1)
                }
            }
            i++
        }
        throw AssertionError("函数体大括号不配对：$signature")
    }
}
