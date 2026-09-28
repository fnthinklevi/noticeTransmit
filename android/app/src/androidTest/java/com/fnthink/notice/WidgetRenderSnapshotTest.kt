package com.fnthink.notice

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Color
import android.util.DisplayMetrics
import android.view.View
import android.view.ViewGroup
import android.widget.FrameLayout
import android.widget.TextView
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.io.FileOutputStream

/**
 * **把小组件画成图片**（视觉取证，不是行为测试）。
 *
 * 存在的理由：桌面小部件是唯一"只有桌面渲染时才看得见"的界面，而桌面不能被自动化 ——
 * 于是它通常的结局是"等某个人某一天瞄一眼"。这里绕开桌面：直接 `RemoteViews.apply()`
 * 出真实的视图树，measure/layout 到真实尺寸后画进 Bitmap。
 * 这画的就是桌面上那一棵树（同一份 layout、同一套 @color、同一段 provider 代码），
 * 所以深浅色、留白、字号、图标位置都在这张图上。
 *
 * 同时留两条**可自动断言**的判据，覆盖 2 语言 × 2 桌面主题 × 2 规格 × 3 态 = 24 张：
 * 1. 每个 TextView 的 Layout 都不许出现省略号、容器高度不许小于文字高度 ——
 *    拦的是"文案加长一个字 / 多塞一行"这类肉眼在缩略图上看不漏的退化（英文尤其容易溢出，
 *    2×2 的内容宽度只有 78dp，所以语言必须进循环）；
 * 2. 三态的卡片平均色必须互相可辨 —— 拦的是"配色按状态走了但走反/没生效"。
 *    像素均值只比"差得够不够远"，不比绝对值（换字号不会误红）。
 */
@RunWith(AndroidJUnit4::class)
class WidgetRenderSnapshotTest {

    private val targetContext: Context
        get() = InstrumentationRegistry.getInstrumentation().targetContext

    private data class Shot(
        val name: String,
        val wide: Boolean,
        val night: Boolean,
        val verdict: WidgetLiveness.Verdict,
    )

    private val states = listOf(
        "pushing" to WidgetLiveness.Verdict.of(WidgetLiveness.State.PUSHING),
        "paused" to WidgetLiveness.Verdict.of(WidgetLiveness.State.PAUSED),
        "closed" to WidgetLiveness.Verdict.of(
            WidgetLiveness.State.CLOSED,
            WidgetLiveness.Reason.KILLED,
        ),
    )

    @Test
    fun everyStateRendersIntoItsOwnColors() {
        I18n.init(targetContext)
        val outDir = File(targetContext.getExternalFilesDir(null), "widget-preview").apply {
            deleteRecursively()
            mkdirs()
        }
        val dm: DisplayMetrics = targetContext.resources.displayMetrics
        val means = mutableMapOf<String, IntArray>()
        // 12 次渲染的截断问题一次跑完全部点名（逐条 assert 会在第一处就中止，
        // 而"改配色/改文案"这一类改动通常一次动好几张卡片）
        val problems = mutableListOf<String>()

        for (locale in listOf("zh", "en")) {
            // 两种语言都要画：2×2 的内容宽度只有 78dp，中文 6 个汉字刚好一行，
            // 而英文按"句"写的提示会溢出 —— 只跑中文就等于没测过英文（实测过才发现）。
            I18n.setLocale(locale)
            for (night in listOf(false, true)) {
                val ctx = if (night) nightContext() else targetContext
                for (wide in listOf(false, true)) {
                    for ((state, verdict) in states) {
                        val size = if (wide) 250 else 110
                        val sizeTag = if (wide) "4x2" else "2x2"
                        val dayNight = if (night) "night" else "day"
                        val where = "$locale/$dayNight/$sizeTag/$state"
                        val w = (size * dm.density).toInt()
                        val h = (110 * dm.density).toInt()
                        val views = PushToggleWidgetProvider.buildRemoteViews(ctx, wide, verdict)
                        val root = FrameLayout(ctx)
                        // 只有两参重载可用（三参那个在公开 SDK 里拿不到）：尺寸由下面的 LayoutParams 决定
                        val painted = views.apply(ctx, root)
                        root.addView(
                            painted,
                            FrameLayout.LayoutParams(w, h),
                        )
                        root.measure(
                            View.MeasureSpec.makeMeasureSpec(w, View.MeasureSpec.EXACTLY),
                            View.MeasureSpec.makeMeasureSpec(h, View.MeasureSpec.EXACTLY),
                        )
                        root.layout(0, 0, w, h)
                        // 先查"有没有被截/被裁"，再画图：省略号与下沿裁切是这类小卡片最常见的缺陷，
                        // 而它们在缩略图上极易看漏（文案加长一个字就会复现，肉眼不会天天盯着）
                        collectClipped(painted, where, problems)
                        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
                        root.draw(android.graphics.Canvas(bmp))
                        val file = File(outDir, "widget_${locale}_${sizeTag}_${dayNight}_$state.png")
                        FileOutputStream(file).use { bmp.compress(Bitmap.CompressFormat.PNG, 100, it) }
                        assertTrue("没写出 ${file.name}", file.length() > 1_000)
                        means["$locale/$dayNight/$state"] = meanColor(bmp)
                        bmp.recycle()
                    }
                }
            }
        }
        android.util.Log.i("WIDGETSHOTS", "写在 ${outDir.absolutePath}：${outDir.list()?.sorted()}")
        // 把三态平均色与两两距离打成可核对的数字：断言只会说"哪两条太近"，
        // 而"到底差多远、该把阈值放在哪"必须看实测值 —— 没有这两行日志，阈值就是拍脑袋。
        for ((key, v) in means) {
            android.util.Log.i("WIDGETMEAN", "$key = rgb(${v[0]},${v[1]},${v[2]}) 亮度=${luminance(v)}")
        }
        for (locale in listOf("zh", "en")) {
            for (night in listOf("day", "night")) {
                for (a in states.map { it.first }) {
                    for (b in states.map { it.first }) {
                        if (a < b) {
                            val d = distance(
                                means.getValue("$locale/$night/$a"),
                                means.getValue("$locale/$night/$b"),
                            )
                            android.util.Log.i("WIDGETDIST", "$locale/$night $a↔$b = $d")
                        }
                    }
                }
            }
        }

        // 三种状态在两种桌面下都必须互相可辨（否则"按状态上色"这件事只是写在代码里）。
        // 与上面的截断检查同一形状：全部记账，最后一次性点名。
        for (locale in listOf("zh", "en")) {
            for (night in listOf("day", "night")) {
                val p = means.getValue("$locale/$night/pushing")
                val q = means.getValue("$locale/$night/paused")
                val c = means.getValue("$locale/$night/closed")
                fun far(a: IntArray, b: IntArray, min: Int, label: String) {
                    val d = distance(a, b)
                    if (d <= min) problems.add("$label 平均色只差 $d（要 > $min）")
                }
                far(p, q, 2_500, "$locale/$night 绿与红")
                far(p, c, 1_500, "$locale/$night 绿与灰")
                far(q, c, 1_500, "$locale/$night 红与灰")
                // 卡片不能画成近黑或近白 —— 那意味着文字与底色撞在一起
                for ((k, v) in means.filterKeys { it.startsWith("$locale/$night/") }) {
                    val lum = luminance(v)
                    if (lum !in 12..244) problems.add("$k 平均亮度 $lum 太极端")
                }
            }
        }
        assertTrue(problems.joinToString("\n"), problems.isEmpty())
    }

    /**
     * 递归查每一段文字：**有没有被省略号截掉、有没有被容器裁掉下沿**。
     *
     * 这条判据比像素均值硬得多，也便宜得多 —— 它读的是 TextView 自己的 Layout，
     * 而"通知…"「已关闭」下沿被切这两类缺陷在缩略图上极易看漏，却是桌面小部件最常见的真实退化。
     */
    private fun collectClipped(view: View, where: String, into: MutableList<String>) {
        if (view is ViewGroup) {
            for (i in 0 until view.childCount) collectClipped(view.getChildAt(i), where, into)
        }
        if (view !is TextView) return
        val text = view.text?.toString().orEmpty()
        val layout = view.layout
        if (text.isEmpty() || layout == null) return
        val label = "$where「$text」"
        for (line in 0 until layout.lineCount) {
            val cut = layout.getEllipsisCount(line)
            if (cut > 0) into.add("$label 第 $line 行被省略号截掉 $cut 个字")
        }
        if (view.height < layout.height) {
            into.add("$label 需要 ${layout.height}px 高，容器只给了 ${view.height}px（下沿被裁）")
        }
    }

    private fun nightContext(): Context {
        val config = Configuration(targetContext.resources.configuration)
        config.uiMode = (config.uiMode and Configuration.UI_MODE_NIGHT_MASK.inv()) or
            Configuration.UI_MODE_NIGHT_YES
        return targetContext.createConfigurationContext(config)
    }

    /** 抽样算平均色：按 8px 网格取样，够稳也快（小卡片没有高频细节）。 */
    private fun meanColor(bmp: Bitmap): IntArray {
        var r = 0L
        var g = 0L
        var b = 0L
        var n = 0L
        var y = 4
        while (y < bmp.height - 4) {
            var x = 4
            while (x < bmp.width - 4) {
                val c = bmp.getPixel(x, y)
                r += Color.red(c)
                g += Color.green(c)
                b += Color.blue(c)
                n++
                x += 8
            }
            y += 8
        }
        return intArrayOf((r / n).toInt(), (g / n).toInt(), (b / n).toInt())
    }

    private fun distance(a: IntArray, b: IntArray): Int {
        val dr = a[0] - b[0]
        val dg = a[1] - b[1]
        val db = a[2] - b[2]
        return dr * dr + dg * dg + db * db
    }

    private fun luminance(c: IntArray): Int =
        (0.2126 * c[0] + 0.7152 * c[1] + 0.0722 * c[2]).toInt()
}
