package com.fnthink.notice

import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 引擎规则 prefs 镜像的跨语言契约（T20：规则入 DB 之后，原生改读 Dart 写的那份镜像）。
 *
 * `BatteryMonitor.parseBatteryRules` 按 `id/type/value/enabled/title` 取值，
 * 而这些键现在由 Dart 侧 `EngineRuleCodec` 写。两端都是字符串，**改一端不会有任何
 * 编译期或运行期报错**：Dart 少写一个 `value`，原生就按 `optInt("value", 20)` 补成 20，
 * 用户配的阈值静默换数（"电量低于 80%"变成"低于 20%"，永远不响或乱响）。
 *
 * 本类把两边的键集合取出来实测比对，并在 Dart 侧镜像少键时立刻变红。
 *
 * ⚠ 解析失败一律算红（`assertTrue(... in ...)` 的锚点先判非空）：静默返回空集合
 * 会让"子集"断言恒真 —— 那是假守卫（base.md（75）的教训）。
 */
class EngineRuleMirrorContractTest {

    private val repoRoot: File = run {
        val candidates = listOf(File("../.."), File("."), File(".."))
        candidates.firstOrNull {
            File(it, "android/app/src/main/kotlin/com/fnthink/notice").isDirectory
        } ?: error("无法定位仓库根目录（cwd=${File(".").absolutePath}）")
    }

    private fun source(path: String): String {
        val f = File(repoRoot, path)
        assertTrue("源文件不存在: ${f.absolutePath}", f.isFile)
        return stripComments(f.readText())
    }

    /** Dart `EngineRuleCodec` 声明的镜像键名单（`uiKeys = [...]`）。 */
    private fun dartMirrorKeys(): Set<String> {
        val src = source("lib/services/engine_rule_codec.dart")
        val block = Regex("""uiKeys\s*=\s*\[([^\]]*)]""").find(src)
        assertTrue("未解析到 Dart 侧 uiKeys —— 常量被改名/删除，本用例已失效", block != null)
        val keys = Regex("'([a-z_]+)'")
            .findAll(block!!.groupValues[1])
            .map { it.groupValues[1] }
            .toSet()
        assertTrue("uiKeys 解析为空，本用例已失效: $keys", keys.isNotEmpty())
        return keys
    }

    /** 原生 `parseBatteryRules` 实际取值的键。 */
    private fun nativeReadKeys(): Set<String> {
        val src = source("android/app/src/main/kotlin/com/fnthink/notice/BatteryMonitor.kt")
        val body = Regex("""fun parseBatteryRules\([\s\S]*?\n    }""").find(src)
        assertTrue("未找到 parseBatteryRules —— 函数已改名，本用例已失效", body != null)
        val keys = Regex("""opt(?:String|Int|Boolean|Long|Double)\(\s*"([a-z_]+)"""")
            .findAll(body!!.value)
            .map { it.groupValues[1] }
            .toSet()
        assertTrue("未解析到任何取值键，本用例已失效", keys.isNotEmpty())
        return keys
    }

    @Test
    fun dartWritesEveryKeyNativeReads() {
        val dart = dartMirrorKeys()
        val native = nativeReadKeys()
        val missing = native - dart
        assertTrue(
            "原生按 $missing 取值，而 Dart 写的镜像里没有这些键 —— " +
                "optXxx 会静默落到默认值（阈值/类型换数，规则永不触发或乱触发）",
            missing.isEmpty()
        )
    }

    @Test
    fun nativeReadKeysAreTheDocumentedFive() {
        // 钉住"原生到底读哪几把键"这件事本身：新增第六把键时必须同时改 Dart 侧，
        // 否则新字段只存在于库里、镜像里没有 = 升级后该字段永远缺失。
        assertTrue(
            "原生取值键集合变了：${nativeReadKeys()}",
            nativeReadKeys() == setOf("id", "type", "value", "enabled", "title")
        )
    }

    @Test
    fun batteryMonitorNoLongerReliesOnNativeMirrorWrite() {
        // T20 撤掉了 `setBatteryRules` / `setTemperatureRules`：镜像由 Dart 单独写。
        // 这里钉住"原生侧只读"这一半（Dart 侧那半在 test/architecture/engine_rule_storage_test.dart）。
        val config = source("android/app/src/main/kotlin/com/fnthink/notice/ConfigManager.kt")
        assertTrue(
            "ConfigManager 里仍有 KEY_BATTERY_RULES 的读取（这是预期的：原生只读镜像）",
            config.contains("fun getBatteryRules()") &&
                config.contains("fun getTemperatureRules()")
        )
        assertTrue(
            "ConfigManager 又长出了规则写入 = 同一把键两个写入者",
            !Regex("""putString\(\s*KEY_(BATTERY|TEMPERATURE)_RULES""").containsMatchIn(config)
        )
        val main = source("android/app/src/main/kotlin/com/fnthink/notice/MainActivity.kt")
        assertTrue(
            "MainActivity 不再写规则镜像（T20）",
            !main.contains("fun setBatteryRules") && !main.contains("fun setTemperatureRules")
        )
    }
}
