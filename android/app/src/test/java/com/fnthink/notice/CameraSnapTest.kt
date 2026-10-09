package com.fnthink.notice

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * 「让这台拍一张」（T124 片C-3 的 `camera:snap`）里**能在 JVM 上断的那一半**：
 * 尺寸挑选规则，与几条"源码里必须在/必须不在"的纪律。
 *
 * 真机上"拍出来的是不是一张能看的照片"只有真机+真相机能证，这里钉的是挑选与门槛。
 */
class CameraSnapTest {

    @Test
    fun `空表回 null，不编一个尺寸出来`() {
        assertNull(CameraSnap.pickSmallest(emptyList()))
    }

    @Test
    fun `挑面积最小的那一个（不是第一个、也不是最大的）`() {
        val small = 320 to 240
        val medium = 640 to 480
        val large = 1920 to 1080
        assertEquals(
            small,
            CameraSnap.pickSmallest(listOf(large, small, medium)),
        )
        assertEquals(medium, CameraSnap.pickSmallest(listOf(medium, large)))
    }

    @Test
    fun `非正尺寸的候选一律排除（0×0 那种不能当选）`() {
        assertNull(CameraSnap.pickSmallest(listOf(0 to 0, -1 to 100)))
        assertEquals(10 to 10, CameraSnap.pickSmallest(listOf(0 to 0, 10 to 10)))
    }

    @Test
    fun `源码纪律：没权限、没界面、两代落盘、不带 while-in-use 之外的新面`() {
        // ⚠ 先剥注释再判（文件头那段说明点了"后台开相机要专门类型"的名，不剥会误报 ——
        //   与 LocationFixTest 同一口坑）。
        val source = stripComments(
            appFile("src/main/kotlin/com/fnthink/notice/CameraSnap.kt").readText(),
        )
        assertTrue(
            "没权限要回 null（空表/失败与它三件事）",
            source.contains("PackageManager.PERMISSION_GRANTED") &&
                source.contains("if (!isGranted(context)) return null"),
        )
        assertTrue(
            "要有「没有可见界面」这道闸（IMPORTANCE_FOREGROUND）",
            source.contains("IMPORTANCE_FOREGROUND"),
        )
        assertTrue(
            "两代落盘都在：29+ 走 MediaStore、24–28 落 app 图片目录",
            source.contains("Build.VERSION_CODES.Q") &&
                source.contains("saveViaMediaStore") &&
                source.contains("saveToAppPictures"),
        )
        assertTrue(
            "不写「已保存到相册」这类话（24–28 上会是假的）——正文组装在 Dart 侧，这里只钉原生不产那句假话",
            !source.contains("已保存到相册"),
        )
        assertTrue(
            "没顺手开第二条权限面：不出现 FOREGROUND_SERVICE 相关声明",
            !source.contains("FOREGROUND_SERVICE"),
        )
    }

    /** 剥掉块注释与整行注释（源码守卫的标配件）。 */
    private fun stripComments(src: String): String =
        src
            .replace(Regex("(?s)/\\*.*?\\*/"), "")
            .lines()
            .filterNot { it.trimStart().startsWith("//") }
            .joinToString("\n")

    private fun appFile(rel: String): java.io.File {
        var dir = java.io.File("").absoluteFile
        while (true) {
            val f = java.io.File(dir, "android/app/$rel")
            if (f.exists()) return f
            dir = dir.parentFile ?: break
        }
        throw AssertionError("找不到 $rel")
    }
}
