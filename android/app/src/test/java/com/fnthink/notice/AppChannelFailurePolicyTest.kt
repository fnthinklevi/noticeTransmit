package com.fnthink.notice

import org.json.JSONException
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.net.ConnectException
import java.net.SocketTimeoutException
import java.net.UnknownHostException

/**
 * T242 token 失败分诊的纯判据测试。
 *
 * 背景（PRD R5）：AppChannelSender.deliver 的 token 阶段此前把**任何**异常都归 BIZ_FAIL
 * （不重试、不入队列）⇒ Doze 下 gettoken 连不上时自建应用通道零自动恢复。
 * 新判据：网络类异常 ⇒ NETWORK_FAIL / 入队重放（replayStored 会重取 token）；
 * TokenFetchException（端点回了业务错误码）⇒ 凭据/配置问题，重试无意义，保持 BIZ_FAIL。
 */
class AppChannelFailurePolicyTest {

    @Test
    fun networkExceptions_areClassifiedAsNetworkFailure() {
        assertTrue(AppChannelFailurePolicy.isNetworkFailure(UnknownHostException("dns fail")))
        assertTrue(AppChannelFailurePolicy.isNetworkFailure(ConnectException("refused")))
        assertTrue(AppChannelFailurePolicy.isNetworkFailure(SocketTimeoutException("timeout")))
        assertTrue(
            AppChannelFailurePolicy.isNetworkFailure(java.net.SocketException("network unreachable")),
        )
        assertTrue(
            AppChannelFailurePolicy.isNetworkFailure(javax.net.ssl.SSLHandshakeException("tls")),
        )
        // OkHttp 其余 IO 形态（响应体读一半断流等）
        assertTrue(AppChannelFailurePolicy.isNetworkFailure(java.io.IOException("broken pipe")))
    }

    @Test
    fun tokenFetchException_isBusinessFailure_notNetwork() {
        // 端点明确回了错误码（凭据错/账号停用）⇒ 重试无意义
        assertFalse(
            AppChannelFailurePolicy.isNetworkFailure(
                AppChannelTokenManager.TokenFetchException(40001, "gettoken 失败 errcode=40001"),
            ),
        )
    }

    @Test
    fun programmingErrors_areNotNetwork() {
        // JSON 解析失败等编程类错误不该被当成网络抖动去重放
        assertFalse(AppChannelFailurePolicy.isNetworkFailure(JSONException("no json")))
        assertFalse(AppChannelFailurePolicy.isNetworkFailure(IllegalStateException("bad state")))
        assertFalse(AppChannelFailurePolicy.isNetworkFailure(NullPointerException("npe")))
    }
}
