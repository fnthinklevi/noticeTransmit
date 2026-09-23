package com.fnthink.notice

import androidx.test.ext.junit.runners.AndroidJUnit4
import io.flutter.plugin.common.StandardMethodCodec
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.nio.ByteBuffer

/**
 * `getChannelDescriptors` 的**设备侧序列化**闸门（第 5 步）。
 *
 * 为什么必须在仪器化侧测：JVM 单测锁的是"我自己认得的可序列化类型"，而这里用的是
 * **Flutter 真正使用的 [StandardMessageCodec]**。编码不合法时它在平台线程抛
 * `IllegalArgumentException: Unsupported value`，而第 5 步起这条调用发生在 splash 的
 * 装配链里 ⇒ 表现是**应用启动即崩**，不是某个页面报错。
 * （同族事故已有先例：`getAppChannels` 直接把 `JSONObject` 交给 `result.success`。）
 *
 * ⚠ Dart 侧的 widget / 集成测试全部给通道装了 mock handler，永远走不到原生这条分支 ——
 * 所以设备侧没有它，就等于整条导出路径零覆盖。
 */
@RunWith(AndroidJUnit4::class)
class ChannelDescriptorsInstrumentedTest {

    @Suppress("UNCHECKED_CAST")
    @Test
    fun descriptorsSurviveFlutterStandardCodec() {
        val descriptors = ChannelRegistry.descriptors() + AppChannelRegistry.descriptors()
        assertEquals("webhook 12 + 应用通道 2", 14, descriptors.size)

        // ⚠ 必须走 MethodCodec 的 envelope，而不是把 encodeMessage 的缓冲直接喂回
        //   decodeMessage：前者带 3 字节长度前缀（由引擎侧剥离），跳过它才解得开 ——
        //   实测直接 round-trip 抛 IllegalArgumentException: Message corrupted。
        //   而 `result.success(payload)` 本来就走 success envelope，与真实通道完全同路径。
        val envelope = StandardMethodCodec.INSTANCE.encodeSuccessEnvelope(descriptors)
        assertNotNull(envelope)
        // 按「线上字节」复制一份再解：encodeSuccessEnvelope 返回的 direct buffer 的
        // position/limit 语义随 embedding 版本变过（实测把它直接回喂 decodeEnvelope 抛
        // BufferUnderflowException），而引擎侧收到的是剥掉长度前缀后的完整字节。
        val decoded = StandardMethodCodec.INSTANCE.decodeEnvelope(
            ByteBuffer.wrap(envelope.toByteArray()),
        )
        assertTrue("解码结果不是 List：${decoded.javaClass}", decoded is List<*>)
        // codec 只保证 Map 的键是 String；这里按解码后的实际结构取值。
        // ⚠ 不要用 `?: org.junit.Assert.fail(...)` 做兜底 —— JUnit 的 fail 返回 void，
        //   elvis 会把元素静态类型推成 Any?，后面每个 `it["key"]` 都编不过。
        val rows = (decoded as List<*>).map { it as Map<String, Any?> }
        assertEquals(descriptors.size, rows.size)

        // 逐条核对解码后的类型：codec 会把 Int 收成 32/64 位两种，Dart 侧统一按 num 取
        val byKey = rows.associateBy { it["key"] as String }
        assertEquals(14, byKey.size)

        val dingtalk = byKey["dingtalk"]!!
        assertEquals("webhook", dingtalk["family"])
        assertEquals("channelTypeDingtalk", dingtalk["labelKey"])
        assertEquals(listOf("oapi.dingtalk.com"), dingtalk["hosts"])
        assertTrue(
            "secretUsed 能力位丢了：Dart 会不再显示签名密钥输入框",
            (dingtalk["capabilities"] as List<*>).contains("secretUsed"),
        )
        // 嵌套的 field Map 也必须原样回来（应用通道的表单全靠它）
        val wecom = byKey["wecom_app"]!!
        val fields = wecom["fields"] as List<Map<String, Any?>>
        assertEquals(listOf("corpid", "agentid", "touser"), fields.map { it["key"] })
        assertEquals(true, fields.first { it["key"] == "corpid" }["required"])
        assertEquals("https://qyapi.weixin.qq.com", wecom["officialBase"])
    }

    /**
     * 取出一个缓冲里「可读的全部字节」。
     *
     * Flutter 的 `*Codec` 编码方法返回 direct buffer，其 position/limit 约定在不同
     * embedding 版本间不一致（已 flip / 停在末尾都见过），所以先归一化到
     * `position=0, limit=capacity` 再读 —— 与引擎侧实际拿到的字节流等价。
     */
    private fun ByteBuffer.toByteArray(): ByteArray {
        val view = duplicate()
        if (view.remaining() == 0) {
            view.position(0)
            view.limit(view.capacity())
        }
        val out = ByteArray(view.remaining())
        view.get(out)
        return out
    }
}
