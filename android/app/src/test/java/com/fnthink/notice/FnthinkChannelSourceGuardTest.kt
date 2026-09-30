package com.fnthink.notice

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * 幻念推送那一族通道的源码守卫（T33 第二片 / §4-9 的前置片0）。
 *
 * 守的是一件事：**签名与身份这条通道不许再回头看 Activity**。
 * 业务上它只需要 `Context`（`FnthinkIdentityStore.identity/sign` 与 `FnthinkInboxDisplay.show`
 * 三个入口一直都吃 `Context`），而基类当初强制 `MainActivity` 让"只需要 Context"这件事
 * 变成了类型上的巧合。代价不在前台，在后台：闹钟 + WorkManager 那一轮是在**新起的引擎**里跑的，
 * 那里根本没有 Activity 可传，于是 `FnthinkChannelHandler` 装不出来 ——
 * 表现不是编译错，而是 Dart 一调 `signFnthinkBytes` 收到 `MissingPluginException`，
 * 而"被杀之后还要去问一次货"这一片要消灭的恰恰是这种**沉默的收不到**。
 *
 * 三条断言各钉一个方向：
 *  - ①（负向，剥注释）这一族里不出现 `MainActivity`：防止"改回 Activity 才顺手"；
 *  - ②（正向）它确实按 `Context` 构造并把这个 context 用到那三处：防止"只改了类型别名，
 *    里面还藏着 `(context as Activity)`"；
 *  - ③（边界）需要 Activity 的那一族**仍然**要 Activity，且分发器收在 `ChannelScope` 上：
 *    防止有人为了过①把整族放宽，然后在跳系统设置页那里改成强转 —— 那才是真的会崩的地方。
 */
class FnthinkChannelSourceGuardTest {

    private val fnthinkHandlerSource: String by lazy {
        stripComments(File(CH + "FnthinkChannelHandler.kt").readText())
    }
    private val dispatcherSource: String by lazy {
        stripComments(File(CH + "ChannelDispatcher.kt").readText())
    }
    private val activitySource: String by lazy {
        stripComments(File(SRC + "MainActivity.kt").readText())
    }

    @Test
    fun fnthinkChannelFamilyDoesNotDependOnActivity() {
        assertFalse(
            "幻念这一族的通道里出现了 Activity（含 `context as Activity` 这种「绕一下」的写法）：" +
                "后台引擎没有 Activity 可传，强转只会在被杀之后那一轮里当场炸",
            fnthinkHandlerSource.contains("Activity"),
        )
        assertTrue(
            "构造函数必须吃 Context 并继承 ChannelScope —— 这是「后台可装」这件事的类型表达",
            fnthinkHandlerSource.contains("class FnthinkChannelHandler(context: Context)") &&
                fnthinkHandlerSource.contains("ChannelScope(context)"),
        )
    }

    @Test
    fun theContextIsActuallyUsedWhereItMatters() {
        // 只改签名不算做到：三处真实的调用必须拿的是这个 context。
        assertTrue(
            "取身份必须用传进来的 context（否则又回去找 Activity）",
            fnthinkHandlerSource.contains("FnthinkIdentityStore.identity(context)"),
        )
        assertTrue(
            "签名字节必须用传进来的 context",
            fnthinkHandlerSource.contains("FnthinkIdentityStore.sign("),
        )
        assertTrue(
            "把一条收件显示成通知必须用传进来的 context",
            fnthinkHandlerSource.contains("FnthinkInboxDisplay.show(context, spec)"),
        )
    }

    @Test
    fun activityBoundFamilyStaysActivityBoundAndDispatcherIsWider() {
        assertTrue(
            "需要 Activity 的那一族不许被一起放宽：跳系统设置页/运行时权限/起服务用的就是 Activity，" +
                "放宽之后只会在运行时强转，而那才是真会崩的地方",
            dispatcherSource.contains("class ChannelHandler") &&
                dispatcherSource.contains("activity: MainActivity"),
        )
        assertTrue(
            "分发器必须收在 ChannelScope 上：否则「能不能被后台装出来」这件事又被类型系统混成一锅",
            dispatcherSource.contains("handlers: List<ChannelScope>"),
        )
    }

    @Test
    fun handlerIsStillWiredIntoTheDispatcher() {
        // 装配点漏接那一类：全部测试仍然绿，只有这里会红。
        assertTrue(
            "MainActivity 仍然要把这一族接进分发器（改成 Context 之后漏了这一行，前台也会从此签不出名）",
            activitySource.contains("FnthinkChannelHandler(this)"),
        )
    }

    private companion object {
        const val SRC = "src/main/kotlin/com/fnthink/notice/"
        const val CH = SRC + "channels/"
    }
}
