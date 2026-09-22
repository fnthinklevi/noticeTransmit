package com.fnthink.notice

import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

/**
 * 通道健康探测（P2）。
 *
 * 对用户配置的 Webhook URL 发起轻量 GET 请求：**任何 HTTP 响应（含 4xx/405）都视为
 * 连通**——各平台的 webhook 端点对 GET 的合法响应不同（Slack 405 / Discord 401 /
 * ntfy 200 JSON feed），无法也无需按业务码判定；只有超时 / DNS 失败 / 连接拒绝
 * 才判定为「连接失败」。业务层健康由最近一次真实推送的送达结果（delivery log）反映。
 *
 * 结果不落盘：Flutter 端触发探测时携带 channelId，结果即时回传并由 Dart 持久化
 * （SharedPreferences），与通道卡片徽标共用一份数据源。
 */
object ChannelHealthProbe {

    data class ProbeResult(
        val reachable: Boolean,
        val latencyMs: Int,
        val httpCode: Int,
    )

    private val client: OkHttpClient by lazy {
        OkHttpClient.Builder()
            .connectTimeout(8, TimeUnit.SECONDS)
            .readTimeout(8, TimeUnit.SECONDS)
            .callTimeout(8, TimeUnit.SECONDS)
            .retryOnConnectionFailure(false)
            .build()
    }

    /** 仅接受 http/https（构造 URL 前置校验） */
    fun isProbeableUrl(url: String): Boolean {
        val u = url.trim()
        return u.startsWith("https://") || u.startsWith("http://")
    }

    /** 同步探测（调用方自行放 IO 线程）；[url] 不合法或网络失败 → reachable=false */
    fun probe(url: String): ProbeResult {
        if (!isProbeableUrl(url)) {
            return ProbeResult(false, 0, 0)
        }
        val start = System.currentTimeMillis()
        return try {
            val request = Request.Builder()
                .url(url.trim())
                .head()
                .addHeader("User-Agent", "NotificationMonitor/1.0")
                .build()
            client.newCall(request).execute().use { response ->
                ProbeResult(
                    reachable = true,
                    latencyMs = (System.currentTimeMillis() - start).toInt(),
                    httpCode = response.code,
                )
            }
        } catch (_: Exception) {
            ProbeResult(false, (System.currentTimeMillis() - start).toInt(), 0)
        }
    }
}
