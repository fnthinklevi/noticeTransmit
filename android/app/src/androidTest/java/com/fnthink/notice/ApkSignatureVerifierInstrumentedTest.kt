package com.fnthink.notice

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/**
 * [ApkSignatureVerifier] 仪表测试（需真机/模拟器，`connectedAndroidTest`）。
 *
 * 覆盖需要真实 Context 的场景（JVM 单测无法覆盖）：
 * - 正例：当前应用自身的 base.apk 必须通过校验（同签名、版本不降级）
 * - 负例 1：非 APK 的垃圾文件必须被拒绝（解析失败 → fail-closed）
 * - 负例 2：不存在的文件必须被拒绝
 * - 负例 3：空路径必须被拒绝
 *
 * 注：构造"自签名 APK"需签名工具链，代价高；这里用「垃圾文件」作为等价负例
 * —— 它同样验证 getPackageArchiveInfo 解析失败时不会降级放行。
 */
@RunWith(AndroidJUnit4::class)
class ApkSignatureVerifierInstrumentedTest {

    private fun context(): Context =
        InstrumentationRegistry.getInstrumentation().targetContext

    @Test
    fun verify_acceptsOwnInstalledApk() {
        val ctx = context()
        val source = ctx.applicationInfo.sourceDir
        val result = ApkSignatureVerifier.verify(ctx, source)
        assertTrue("自身 APK 应通过校验: ${result.detail}", result.valid)
    }

    @Test
    fun verify_rejectsGarbageFile() {
        val ctx = context()
        val junk = File(ctx.cacheDir, "junk.apk").apply {
            writeText("this is definitely not an apk")
        }
        try {
            val result = ApkSignatureVerifier.verify(ctx, junk.absolutePath)
            assertFalse("垃圾文件必须被拒绝", result.valid)
            assertTrue(result.detail.isNotEmpty())
        } finally {
            junk.delete()
        }
    }

    @Test
    fun verify_rejectsMissingFile() {
        val ctx = context()
        val result = ApkSignatureVerifier.verify(ctx, "${ctx.cacheDir}/no_such_file.apk")
        assertFalse("不存在的文件必须被拒绝", result.valid)
    }

    @Test
    fun verify_rejectsEmptyPath() {
        val result = ApkSignatureVerifier.verify(context(), "")
        assertFalse("空路径必须被拒绝", result.valid)
    }
}
