package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * MethodChannel 嵌套结构序列化的静态源码守卫（JVM 直测，无需 Android 运行时）。
 *
 * **背景（v1.5.68 聚合推送根因一）**：`setNotificationRules` 曾把 MethodChannel 解码的
 * 嵌套 `List<Map>` 直接 `JSONObject.put(k, v)`——Android 的 `JSONObject.put(String, Object)`
 * **不转换 Collection/Map**，原始对象在 `toString()` 时序列化为带引号的 Java 字符串
 * （如 `"[{id=..., type=...}]"`，非合法 JSON），原生端 `optJSONArray("conditions")`
 * 读回恒 null → `RuleEngine.evaluate()` 首行 `?: return false` →
 * **原生规则引擎从未匹配过任何规则**（聚合/延迟/静默/记录全部失效，自上线起）。
 *
 * 已修：新增 `toNativeJson()` 递归转换（Map → JSONObject、List → JSONArray、标量原样）。
 *
 * **本类锁定的契约**：
 * 1. `toNativeJson` 必须存在且**递归自调用**（嵌套任意深度都要转换）；
 * 2. 所有接收 `List<Map<String, ...>>`（MethodChannel 解码结构）的写入函数，
 *    函数体必须调用 `toNativeJson(` ——例外仅限**全标量扁平结构白名单**
 *    （`setWebhookChannels` / `setBatteryRules`：逐字段显式取值，无嵌套字段）；
 * 3. `setNotificationRules` 禁止「迭代解码 Map 后直接 put」的危险模式。
 *
 * 新增通道写入函数时：若参数含 `List<Map<...>>`，**必须经 `toNativeJson`**，
 * 否则本守卫失败；确属全标量扁平结构，加入 [flatAllowlist] 并注明原因。
 *
 * ⚠ 断言前剥离注释（stripComments）——注释里的同名字样会误伤守卫（历史教训，
 * 见 MergePushLockContractTest 头注释）。反证方式：把 `setNotificationRules`
 * 改回 `obj.put(k, v)` 直写循环 → 本类必须变红。
 */
class NativeJsonSerializationContractTest {

    private val repoRoot: File = run {
        // Gradle 测试工作目录随 AGP/启动方式变化，逐个探测而不猜路径
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull { File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory }
            ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun kotlinSource(name: String): String {
        val f = File(
            repoRoot,
            "android/app/src/main/kotlin/com/fnthink/notice/$name"
        )
        assertTrue("源文件不存在: ${f.absolutePath}", f.isFile)
        return f.readText()
    }

    /** 按函数名提取函数体（大括号配平），并剥离注释——断言只看可执行代码 */
    private fun functionBody(source: String, funName: String): String {
        val marker = "fun $funName"
        val idx = source.indexOf(marker)
        assertTrue("未找到函数 $funName", idx >= 0)
        val bodyStart = source.indexOf('{', idx)
        assertTrue("函数 $funName 缺少函数体", bodyStart >= 0)
        var depth = 0
        var i = bodyStart
        while (i < source.length) {
            when (source[i]) {
                '{' -> depth++
                '}' -> {
                    depth--
                    if (depth == 0) break
                }
            }
            i++
        }
        return stripComments(source.substring(bodyStart, i + 1))
    }

    private fun stripComments(code: String): String {
        val noBlock = Regex("""/\*[\s\S]*?\*/""").replace(code, " ")
        return noBlock.lineSequence()
            .joinToString("\n") { line ->
                val idx = line.indexOf("//")
                if (idx >= 0) line.substring(0, idx) else line
            }
    }

    /**
     * 全标量扁平结构白名单：这些函数接收 `List<Map<...>>` 但**不存在嵌套字段风险**：
     * - `setWebhookChannels` / `setBatteryRules`：逐字段显式取标量（String/Int/Boolean）；
     * - `saveInstalledAppsCache`：用 `JSONObject(Map)` **拷贝构造器**——该构造器内部
     *   递归 wrap（Map→JSONObject / Collection→JSONArray），与手动 `put(k, v)` 不同，
     *   天然安全。
     * ⚠ 若未来给这些配置增加嵌套字段，手动 put 写法必须改走 `toNativeJson` 并把
     * 函数移出本白名单——否则会复发 v1.5.68 的同类缺陷。
     */
    private val flatAllowlist = setOf(
        "setWebhookChannels",
        "setBatteryRules",
        "saveInstalledAppsCache",
    )

    // ===== 约束 1：toNativeJson 存在且递归自调用 =====

    @Test
    fun toNativeJsonExistsAndRecurses() {
        val source = kotlinSource("MainActivity.kt")
        val body = functionBody(source, "toNativeJson")
        assertTrue(
            "toNativeJson 必须处理 Map 分支（Map → JSONObject）",
            body.contains("is Map<*, *>")
        )
        assertTrue(
            "toNativeJson 必须处理 List 分支（List → JSONArray）",
            body.contains("is List<*>")
        )
        // 递归：Map 分支与 List 分支各自至少自调用一次（共 ≥ 2 处，减去定义不计入函数体）
        val selfCalls = Regex("""toNativeJson\(""").findAll(body).count()
        assertTrue(
            "toNativeJson 缺少递归自调用（嵌套深度 >1 时不会被转换）—— 实际自调用 $selfCalls 处",
            selfCalls >= 2
        )
    }

    // ===== 约束 2：所有 List<Map<...>> 结构化写入函数必须经 toNativeJson（白名单除外）=====

    @Test
    fun allStructuredWritersConvertViaToNativeJson() {
        val source = kotlinSource("MainActivity.kt")
        // 提取所有接收 List<Map<String, ...>> 参数的函数（MethodChannel 解码数据）
        val signatureRegex = Regex("""fun\s+(\w+)\s*\([^)]*List<Map<String""")
        val offenders = mutableListOf<String>()
        for (match in signatureRegex.findAll(source)) {
            val name = match.groupValues[1]
            if (name in flatAllowlist) continue
            val body = functionBody(source, name)
            if (!body.contains("toNativeJson(")) offenders.add(name)
        }
        assertTrue(
            "未找到任何 List<Map<...>> 写入函数（源码结构可能已变，需更新本测试）",
            signatureRegex.containsMatchIn(source)
        )
        assertTrue(
            "以下函数接收 MethodChannel 解码的 List<Map<...>> 但未经 toNativeJson 转换：" +
                "${offenders.joinToString()}。Android 的 JSONObject.put() 不转换 Collection/Map，" +
                "嵌套结构会被序列化成 Java 字符串导致原生端读回 null（v1.5.68 根因一）。" +
                "全标量扁平结构可加入 flatAllowlist 并注明原因。",
            offenders.isEmpty()
        )
    }

    // ===== 约束 3：setNotificationRules 禁止「迭代解码 Map 后直接 put」的危险模式 =====

    @Test
    fun setNotificationRulesHasNoDirectMapIterationPut() {
        val body = functionBody(
            kotlinSource("MainActivity.kt"),
            "setNotificationRules"
        )
        assertTrue(
            "setNotificationRules 必须经 toNativeJson(rule) 转换后入列",
            body.contains("toNativeJson(rule)")
        )
        assertFalse(
            "setNotificationRules 出现「for ((k, v) in ...) 直接 put」的危险模式 —— " +
                "嵌套 List<Map> 会被序列化成 Java 字符串，conditions/actions 读回恒 null" +
                "（v1.5.68 根因一，勿回退）",
            Regex("""for\s*\(\((k,\s*v)\)\s*in""").containsMatchIn(body)
        )
    }
}
