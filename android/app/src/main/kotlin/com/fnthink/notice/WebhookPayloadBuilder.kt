package com.fnthink.notice

import org.json.JSONObject

object WebhookPayloadBuilder {

    enum class WebhookType {
        GENERIC,
        WECHAT_WORK,
        DINGTALK,
        FEISHU
    }

    fun detectType(url: String): WebhookType {
        return when {
            url.contains("qyapi.weixin.qq.com") || url.contains("weixin.qq.com") -> WebhookType.WECHAT_WORK
            url.contains("oapi.dingtalk.com") || url.contains("dingtalk") -> WebhookType.DINGTALK
            url.contains("feishu.cn") || url.contains("larksuite.com") -> WebhookType.FEISHU
            else -> WebhookType.GENERIC
        }
    }

    fun buildPayload(
        type: WebhookType,
        title: String,
        content: String,
        appName: String = "",
        packageName: String = "",
        time: String = "",
        deviceName: String = "",
        notifyType: String = "",
        extras: Map<String, String> = emptyMap()
    ): String {
        return when (type) {
            WebhookType.GENERIC -> buildGeneric(
                title = title,
                content = content,
                appName = appName,
                packageName = packageName,
                time = time,
                deviceName = deviceName,
                notifyType = notifyType,
                extras = extras
            )
            WebhookType.WECHAT_WORK -> buildWeChatWork(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName,
                notifyType = notifyType
            )
            WebhookType.DINGTALK -> buildDingTalk(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName
            )
            WebhookType.FEISHU -> buildFeishu(
                title = title,
                content = content,
                appName = appName,
                time = time,
                deviceName = deviceName
            )
        }
    }

    fun buildTestPayload(type: WebhookType, deviceName: String): String {
        return when (type) {
            WebhookType.GENERIC -> JSONObject().apply {
                put("type", "test")
                put("title", "测试通知")
                put("content", "这是一条测试消息，Webhook 配置成功！")
                put("deviceName", deviceName)
                put("timestamp", System.currentTimeMillis())
            }.toString()

            WebhookType.WECHAT_WORK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", "【测试通知】\n这是一条测试消息，Webhook 配置成功！\n\n设备：$deviceName")
                })
            }.toString()

            WebhookType.DINGTALK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", "【测试通知】\n这是一条测试消息，Webhook 配置成功！\n\n设备：$deviceName")
                })
            }.toString()

            WebhookType.FEISHU -> JSONObject().apply {
                put("msg_type", "text")
                put("content", JSONObject().apply {
                    put("text", "【测试通知】\n这是一条测试消息，Webhook 配置成功！\n\n设备：$deviceName")
                })
            }.toString()
        }
    }

    private fun buildGeneric(
        title: String,
        content: String,
        appName: String,
        packageName: String,
        time: String,
        deviceName: String,
        notifyType: String,
        extras: Map<String, String>
    ): String {
        return JSONObject().apply {
            put("title", title)
            put("content", content)
            put("appName", appName)
            put("packageName", packageName)
            put("time", time)
            put("deviceName", deviceName)
            put("type", notifyType)
            put("timestamp", System.currentTimeMillis())
            for ((k, v) in extras) {
                put(k, v)
            }
        }.toString()
    }

    private fun buildWeChatWork(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String,
        notifyType: String
    ): String {
        val typeLabel = when (notifyType) {
            "sms" -> "【新短信】"
            "call_incoming" -> "【来电提醒】"
            "call_answered" -> "【通话中】"
            "call_ended" -> "【通话结束】"
            "battery_charging" -> "【充电提醒】"
            "battery_full" -> "【电量充满】"
            "battery_low_30" -> "【低电量提醒】"
            "battery_low_20" -> "【低电量提醒】"
            else -> if (appName.isNotEmpty()) "【$appName】" else "【通知提醒】"
        }

        val sb = StringBuilder()
        sb.append("$typeLabel\n")
        if (title.isNotEmpty()) {
            sb.append("标题：$title\n")
        }
        if (content.isNotEmpty()) {
            sb.append("内容：$content\n")
        }
        if (time.isNotEmpty()) {
            sb.append("时间：$time\n")
        }
        if (deviceName.isNotEmpty()) {
            sb.append("设备：$deviceName")
        }

        return JSONObject().apply {
            put("msgtype", "text")
            put("text", JSONObject().apply {
                put("content", sb.toString())
            })
        }.toString()
    }

    private fun buildDingTalk(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String
    ): String {
        val prefix = if (appName.isNotEmpty()) "【$appName】" else "【通知提醒】"
        val sb = StringBuilder()
        sb.append("$prefix\n")
        if (title.isNotEmpty()) {
            sb.append("标题：$title\n")
        }
        if (content.isNotEmpty()) {
            sb.append("内容：$content\n")
        }
        if (time.isNotEmpty()) {
            sb.append("时间：$time\n")
        }
        if (deviceName.isNotEmpty()) {
            sb.append("设备：$deviceName")
        }

        return JSONObject().apply {
            put("msgtype", "text")
            put("text", JSONObject().apply {
                put("content", sb.toString())
            })
        }.toString()
    }

    private fun buildFeishu(
        title: String,
        content: String,
        appName: String,
        time: String,
        deviceName: String
    ): String {
        val prefix = if (appName.isNotEmpty()) "【$appName】" else "【通知提醒】"
        val sb = StringBuilder()
        sb.append("$prefix\n")
        if (title.isNotEmpty()) {
            sb.append("标题：$title\n")
        }
        if (content.isNotEmpty()) {
            sb.append("内容：$content\n")
        }
        if (time.isNotEmpty()) {
            sb.append("时间：$time\n")
        }
        if (deviceName.isNotEmpty()) {
            sb.append("设备：$deviceName")
        }

        return JSONObject().apply {
            put("msg_type", "text")
            put("content", JSONObject().apply {
                put("text", sb.toString())
            })
        }.toString()
    }

    fun buildSmsPayload(
        type: WebhookType,
        sender: String,
        message: String,
        time: String,
        deviceName: String
    ): String {
        return when (type) {
            WebhookType.GENERIC -> JSONObject().apply {
                put("type", "sms")
                put("sender", sender)
                put("message", message)
                put("time", time)
                put("deviceName", deviceName)
                put("timestamp", System.currentTimeMillis())
            }.toString()

            WebhookType.WECHAT_WORK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", "【新短信】\n" +
                            "发送号码：$sender\n" +
                            "短信内容：$message\n" +
                            "接收时间：$time\n" +
                            "设备：$deviceName")
                })
            }.toString()

            WebhookType.DINGTALK -> JSONObject().apply {
                put("msgtype", "text")
                put("text", JSONObject().apply {
                    put("content", "【新短信】\n" +
                            "发送号码：$sender\n" +
                            "短信内容：$message\n" +
                            "接收时间：$time\n" +
                            "设备：$deviceName")
                })
            }.toString()

            WebhookType.FEISHU -> JSONObject().apply {
                put("msg_type", "text")
                put("content", JSONObject().apply {
                    put("text", "【新短信】\n" +
                            "发送号码：$sender\n" +
                            "短信内容：$message\n" +
                            "接收时间：$time\n" +
                            "设备：$deviceName")
                })
            }.toString()
        }
    }

    fun buildCallPayload(
        type: WebhookType,
        state: String,
        phoneNumber: String,
        time: String,
        durationStr: String = "",
        deviceName: String
    ): String {
        val title = when (state) {
            "ringing" -> "来电提醒"
            "answered" -> "通话中"
            "ended" -> "通话结束"
            else -> "电话通知"
        }

        return when (type) {
            WebhookType.GENERIC -> JSONObject().apply {
                put("type", "call_$state")
                put("phoneNumber", phoneNumber)
                put("callState", state)
                put("time", time)
                if (durationStr.isNotEmpty()) put("duration", durationStr)
                put("deviceName", deviceName)
                put("timestamp", System.currentTimeMillis())
            }.toString()

            WebhookType.WECHAT_WORK -> {
                var content = "【$title】\n" +
                        "来电号码：$phoneNumber\n" +
                        "时间：$time\n"
                if (durationStr.isNotEmpty()) {
                    content += "通话时长：$durationStr\n"
                }
                content += "设备：$deviceName"

                JSONObject().apply {
                    put("msgtype", "text")
                    put("text", JSONObject().apply {
                        put("content", content)
                    })
                }.toString()
            }

            WebhookType.DINGTALK -> {
                var content = "【$title】\n" +
                        "来电号码：$phoneNumber\n" +
                        "时间：$time\n"
                if (durationStr.isNotEmpty()) {
                    content += "通话时长：$durationStr\n"
                }
                content += "设备：$deviceName"

                JSONObject().apply {
                    put("msgtype", "text")
                    put("text", JSONObject().apply {
                        put("content", content)
                    })
                }.toString()
            }

            WebhookType.FEISHU -> {
                var content = "【$title】\n" +
                        "来电号码：$phoneNumber\n" +
                        "时间：$time\n"
                if (durationStr.isNotEmpty()) {
                    content += "通话时长：$durationStr\n"
                }
                content += "设备：$deviceName"

                JSONObject().apply {
                    put("msg_type", "text")
                    put("content", JSONObject().apply {
                        put("text", content)
                    })
                }.toString()
            }
        }
    }
}
