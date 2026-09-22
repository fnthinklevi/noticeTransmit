package com.fnthink.notice

// 静态源码守卫的共用工具（与 test/support/source_guards.dart 同规则）。
//
// 本项目大量 Kotlin 守卫是「读源文件 + 字符串断言」。这类守卫有两个失效模式：
//
// 1. **必须剥注释**：否则「解释为什么改了」的注释文本会污染断言
//    （MergePushLockContractTest 首版就被注释里的同名字样误伤过）。
// 2. **剥注释必须引号感知**：按「行内首个 //」截断会把 "https://host"
//    这类字符串字面量从中间切掉，使被守卫的集合静默少项——
//    守卫变绿，但保护已经没了（「测试通过 ≠ 有保护」）。
//
// 所以实现只留这一份：各测试类不再各自复制，避免逐份漂移。

/** 剥离块注释与行注释，只留可执行代码。行注释按引号状态判定。 */
internal fun stripComments(source: String): String {
    val withoutBlock = Regex("""/\*[\s\S]*?\*/""").replace(source, "")
    return withoutBlock.split('\n').joinToString("\n") { line ->
        var quote: Char? = null
        var escaped = false
        var cut = -1
        var i = 0
        while (i < line.length && cut < 0) {
            val ch = line[i]
            if (quote != null) {
                when {
                    escaped -> escaped = false
                    ch == '\\' -> escaped = true
                    ch == quote -> quote = null
                }
            } else if (ch == '"' || ch == '\'') {
                quote = ch
            } else if (ch == '/' && i + 1 < line.length && line[i + 1] == '/') {
                cut = i
            }
            i++
        }
        if (cut >= 0) line.substring(0, cut) else line
    }
}
