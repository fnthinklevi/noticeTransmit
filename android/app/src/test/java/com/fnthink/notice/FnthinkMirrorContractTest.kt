package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 幻念那一族的**跨语言镜像**键名守卫（T94 片4c）。
 *
 * 这一族有两道字符串契约，两道都是"改一端不会报错，只是行为不对"：
 *
 * | 缝 | Dart | 原生 | 改坏的样子 |
 * |---|---|---|---|
 * | 通道配置镜像 | `fnthink_channel_mirror.dart` 的 `encodeFnthinkChannelMirror` 写 5 个键 | [ConfigManager.getFnthinkChannelConfigs] 按 5 个键读 | `target_kind` 一改名，原生全部按缺省 `device` 处理 ⇒ **每一条 webhook 通道都被当成地址码**，发不出去而界面上毫无异样 |
 * | 待发队列 | `fnthink_fanout_entrypoint.dart` 的 `parseFanoutBatch` 读 6 个键 | [FnthinkFanoutQueue.buildItem] 写 11 个键 | `content` 一改名，正文恒为空 ⇒ 对方收到一条空消息；`targets` 一改名，那一轮空跑 |
 *
 * 为什么不在两侧各写一份"期望集合"就完事：那样两份期望会**一起漂**。改 Dart 的键、
 * 顺手改 Dart 那份用例 ⇒ 两侧全绿，而原生读到的是空表。所以这里两边都**从源码现取**
 * （[EngineRuleMirrorContractTest] 同一套路）。
 *
 * ⚠ 解析失败一律算红：每个提取点后面都跟着"非空 + 等于文档化集合"的断言，
 *   静默返回空集合会让子集断言恒真 —— 那是假守卫（base.md（75）的教训）。
 * ⚠ 两个方向的子集不一样：镜像那侧是**原生读的 ⊆ Dart 写的**（原生多读一个键 =
 *   静默取默认值）；队列那侧是**Dart 读的 ⊆ 原生写的**（原生多写一个键只是没人用，
 *   Dart 多读一个键才是空值）。方向写反的话，断言会在真正出事的那一侧恒真。
 */
class FnthinkMirrorContractTest {

    // JUnit 是 (message, value)，与 kotlin.test 相反。
    private fun ok(message: String, condition: Boolean) = assertTrue(message, condition)

    private fun <T> eq(message: String, expected: T, actual: T) =
        assertEquals(message, expected, actual)

    private fun repoFile(rel: String): File {
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, rel)
            if (candidate.exists()) return candidate
            dir = dir.parentFile
        }
        throw IllegalStateException("未找到 $rel（cwd=${File("").absolutePath}）")
    }

    private fun dart(rel: String) = stripComments(repoFile(rel).readText(Charsets.UTF_8))

    private fun kt(rel: String) =
        stripComments(repoFile("app/src/main/kotlin/com/fnthink/notice/$rel").readText(Charsets.UTF_8))

    /**
     * 从 [marker] 起取第一个 `{` 配平到它的 `}`，返回**里面**那段。
     *
     * 两个必须：① 按配平取而不是按下一行取 —— 这四处的排版（dart format / ktlint）会折行，
     * 按行取会在某次格式化后悄悄只取到半段，那时的读数是"少几个键"，与真坏掉同形；
     * ② [marker] 必须带**签名**（`… parseFanoutBatch(`）而不是光一个函数名 ——
     * 只给名字时 `indexOf` 会先撞上文件前面的**调用点**，取出来的是调用点所在的那段。
     */
    private fun braced(src: String, marker: String, where: String): String {
        val at = src.indexOf(marker)
        ok("未找到 `$marker`（$where）—— 声明已改名或删除，本用例已失效", at >= 0)
        val open = src.indexOf('{', at)
        ok("`$marker` 之后没有 `{`（$where），本用例已失效", open >= 0)
        var depth = 0
        for (i in open until src.length) {
            when (src[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) return src.substring(open + 1, i)
                }
            }
        }
        ok("`$marker` 的花括号没配平（$where），本用例已失效", false)
        return ""
    }

    private fun matches(pattern: String, block: String): Set<String> =
        Regex(pattern).findAll(block).map { it.groupValues[1] }.toSet()

    private fun nonEmpty(what: String, keys: Set<String>): Set<String> {
        ok("$what 解析为空（形状变了？）—— 本用例已失效：$keys", keys.isNotEmpty())
        return keys
    }

    // ---------------------------------------------------------------- 缝一：通道配置镜像

    /** Dart `encodeFnthinkChannelMirror` 里映射字面量写的键。 */
    private fun dartMirrorWriteKeys(): Set<String> = nonEmpty(
        "Dart 侧镜像键名",
        matches(
            // ⚠ 字符类必须是 [A-Za-z_]+：写成 [a-z_]+ 时，一个 camelCase 的键**整条匹配不上**，
            // 于是"原生开始按 targetKind 取值"这件事在尺上完全不可见 ——
            // 子集断言照样绿（实测：反证 M2 只红在"键集合等于那五个"这一条）。
            // 这就是尺的口径比它量的东西窄：不是判据漏了，是尺没量到。
            """'([A-Za-z_]+)'\s*:""",
            braced(dart("lib/services/fnthink_channel_mirror.dart"), "String encodeFnthinkChannelMirror(", "镜像编码"),
        ),
    )

    /** 原生 `getFnthinkChannelConfigs` 实际 `optString` 的键。 */
    private fun nativeMirrorReadKeys(): Set<String> = nonEmpty(
        "原生侧镜像取值键",
        matches(
            """optString\(\s*"([A-Za-z_]+)"""",
            braced(kt("ConfigManager.kt"), "fun getFnthinkChannelConfigs(", "镜像解析"),
        ),
    )

    @Test
    fun `镜像：原生读的每个键 Dart 都写了`() {
        val missing = nativeMirrorReadKeys() - dartMirrorWriteKeys()
        ok(
            "原生按 $missing 取值，而 Dart 写的镜像里没有这些键 —— optString 会静默取缺省：" +
                "`target_kind` 那一条尤其致命（全部通道被当成设备地址码，一条也发不出去）",
            missing.isEmpty(),
        )
    }

    @Test
    fun `镜像：两侧的键集合就是文档化的那五个`() {
        // 钉住"到底是哪几个"本身：新增第六个键时必须同时改另一侧，
        // 否则新字段只存在于库里 / 镜像里没有 = 升级后该字段永远缺失。
        val five = setOf("id", "name", "target_kind", "target", "role")
        eq("Dart 侧写的键集合变了", five, dartMirrorWriteKeys())
        eq("原生侧读的键集合变了", five, nativeMirrorReadKeys())
    }

    // ---------------------------------------------------------------- 缝二：待发队列

    /** Dart `parseFanoutBatch` 真正下标取的那几个键（`raw[...]` 与 `t[...]`）。 */
    private fun dartFanoutReadKeys(): Set<String> = nonEmpty(
        "Dart 侧待发项取值键",
        matches(
            """(?:raw|t)\['([A-Za-z_]+)'\]""",
            braced(dart("lib/services/fnthink_fanout_entrypoint.dart"), "parseFanoutBatch(String batchJson)", "待发项解析"),
        ),
    )

    /** 原生 `buildItem` 写进那一项的键。 */
    private fun nativeFanoutWriteKeys(): Set<String> = nonEmpty(
        "原生侧待发项写入键",
        matches(
            """put\("([A-Za-z_]+)"""",
            braced(kt("FnthinkFanoutQueue.kt"), "internal fun buildItem(", "待发项构造"),
        ),
    )

    @Test
    fun `待发项：Dart 读的每个键原生都写了`() {
        val missing = dartFanoutReadKeys() - nativeFanoutWriteKeys()
        ok(
            "Dart 按 $missing 取值，而原生那一项里没有这些键 —— 取到的是 null，" +
                "`content`/`title` 那几个会让对方收到一条空消息，`targets` 那一个会让整轮空跑",
            missing.isEmpty(),
        )
    }

    @Test
    fun `待发项：原生写的键集合固定为十一个`() {
        // 反向也钉住：原生多写一个键时这里会红，逼人回答"Dart 到底要不要读它"。
        // 不钉的后果已经现过一次 —— `viaBackup` 写了没人读（见 roadmap 的那条债）。
        eq(
            "原生侧待发项写入键集合变了（新增/删除字段必须同时决定 Dart 要不要读）",
            setOf(
                "channel_id", "target_kind", "target",
                "id", "title", "content", "appName", "time", "deviceName", "viaBackup", "targets",
            ),
            nativeFanoutWriteKeys(),
        )
        eq(
            "Dart 侧取值键集合变了（多读一个键 ⇒ 原生没写时恒为 null）",
            setOf("id", "title", "content", "appName", "targets", "target"),
            dartFanoutReadKeys(),
        )
    }

    // ---------------------------------------------------------------- prefs 键名与回报口

    private fun dartConst(name: String): String {
        val pattern = """const String $name = '([^']+)';"""
        val m = Regex(pattern).find(dart("lib/services/fnthink_channel_mirror.dart"))
            ?: Regex(pattern).find(dart("lib/services/fnthink_fanout_entrypoint.dart"))
        ok("Dart 侧没有 `const String $name = '…'` —— 常量被改名/删除，本用例已失效", m != null)
        return m!!.groupValues[1]
    }

    private fun nativeConst(file: String, name: String): String {
        val m = Regex("""(?:private )?const val $name = "([^"]+)"""")
            .find(kt(file))
        ok("$file 里没有 `const val $name = \"…\"` —— 常量被改名/删除，本用例已失效", m != null)
        return m!!.groupValues[1]
    }

    @Test
    fun `prefs 键名两侧同串（原生那份多一个 flutter 前缀）`() {
        // 前缀不是这里选的字符串，是 shared_preferences 的存储形状 —— 所以要钉的是
        // 「去掉前缀之后两侧同名」，而不是把前缀也当常量抄一遍。
        for ((dartName, nativeFile, nativeName) in listOf(
            Triple("kFnthinkChannelMirrorKey", "ConfigManager.kt", "KEY_FNTHINK_CHANNELS"),
            Triple("kFnthinkFanoutPendingKey", "FnthinkFanoutQueue.kt", "KEY_PENDING"),
            Triple("kFnthinkFanoutHandleKey", "FnthinkFanoutWorker.kt", "KEY_HANDLE"),
        )) {
            val d = dartConst(dartName)
            eq(
                "$dartName ($d) 与 $nativeName 不是同串：" +
                    "键对不上 ⇒ 原生读不到那一行，表现为「静默空转」而不是报错",
                "flutter.$d",
                nativeConst(nativeFile, nativeName),
            )
        }
    }

    @Test
    fun `入口 handle 的存取类型成对（Dart setInt 对原生 getLong）`() {
        // 类型也是契约：原生那一侧 `getLong` 拿一个 String 会在运行时抛 ClassCastException，
        // 而它发生在**第一条通知**进来的时候（其余一切正常）。
        val entry = dart("lib/services/fnthink_fanout_entrypoint.dart")
        ok(
            "Dart 侧不是 setInt 写入口 handle：本仓库 shared_preferences 的 setInt 落盘成长整型，" +
                "改成别的写法会让原生 getLong 在第一条通知上抛 ClassCastException",
            Regex("""prefs\.setInt\(kFnthinkFanoutHandleKey,""").containsMatchIn(entry),
        )
        ok(
            "原生侧不是 getLong 读入口 handle：与上面的 setInt 不成对",
            Regex("""getLong\(KEY_HANDLE,""").containsMatchIn(kt("FnthinkFanoutWorker.kt")),
        )
    }

    @Test
    fun `后台那一轮的回报口两侧同串`() {
        // 不同串的后果：那一轮跑完了但原生等不到回报，WorkManager 挂到超时才返回。
        val dartChannel = dartConst("kFnthinkFanoutChannel")
        eq(
            "Dart 侧的回报口名与 FnthinkFanoutWorker.FANOUT_CHANNEL 不同串 ⇒ fanoutDone 送不出去",
            dartChannel,
            nativeConst("FnthinkFanoutWorker.kt", "FANOUT_CHANNEL"),
        )
    }

    @Test
    fun `镜像只有一个写入者（原生那一侧不许也写这一把键）`() {
        // 与 T20 电池规则同一道保险：同一把键两个写入者时，最后一次写的那一侧赢，
        // 而"谁赢"取决于时序 —— 表现是用户改了配置却不生效，偶发。
        val cfg = kt("ConfigManager.kt")
        ok(
            "ConfigManager 里出现了对 KEY_FNTHINK_CHANNELS 的写入（这是预期的：原生只读镜像）",
            cfg.contains("fun getFnthinkChannelConfigs()"),
        )
        ok(
            "ConfigManager 又长出了镜像写入 = 同一把键两个写入者，最后写的那一侧赢",
            !Regex("""putString\(\s*KEY_FNTHINK_CHANNELS""").containsMatchIn(cfg),
        )
    }
}
