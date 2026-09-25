package com.fnthink.notice

/**
 * 邮件通道的描述符（T08-C）。
 *
 * **为什么原生侧以前没有这张表**：邮件族从第一天起就是 Dart 手写的 —— 原生只有
 * `EmailSender`（发）与 `EmailManager`（存），两边各自读一批列名，表单事实（哪些字段、
 * 必填、默认端口、SSL 开关、11 条预置模板）全在页面里。于是同一件事最多有六份抄本：
 * 端口 465 在 Dart 三处 + 模型两处 + `EmailManager.kt:125`，默认主题/正文在
 * `EmailSender.kt:206,212` 与两条"伪装成提示文案"的 ARB 键里各一份，预置模板正文
 * 只有 Dart 那份（**所以英文界面点预置会往用户配置里写中文**）。
 *
 * **这张表是谁的事实**：字段的存储键名、控件形态、必填、留空默认值、提示词条、预置档位。
 * 不谁的事实：发送行为（`EmailSender` 仍然自己决定 SSL/STARTTLS 与超时）。
 *
 * ⚠ 字段 [fields] 的 key 必须是 `EmailManager`/`EmailSender` **真的会读**的列名，
 * 由 `ChannelDescriptorExportTest.emailFieldsMatchWhatNativeActuallyReads` 双向核对 ——
 * 表里多一个键 = 用户填了没人读（存了、读得出、没人用那一类），少一个键 = 发送时拿空值。
 */
object EmailChannelSpec {

    /** 描述符 family（Dart 侧 `ChannelDescriptorService.email` 按它取） */
    const val FAMILY = "email"

    /**
     * 稳定 key。**刻意用 `email` 而不是某个主机名**：邮件族只有一个通道类型，
     * 送达键是 `chan:email`（多邮箱在键上塌缩成同一个，见 active_channels），
     * 而 `iconKey == key` 是导出守卫的硬要求。
     */
    const val KEY = "email"

    /** 缺省端口：SSL 直连端口。表与 `EmailManager` 读库时的兜底共用这一个常量。 */
    const val DEFAULT_PORT = 465

    /** 缺省传输方式（true = SSL 直连；false = STARTTLS） */
    const val DEFAULT_USE_SSL = true

    /** 表单顺序 = 这里 List 的顺序 = 校验失败时点名顺序（页面不得另排一遍） */
    val fields: List<FieldSpec> = listOf(
        FieldSpec(
            key = "smtpHost",
            labelKey = "smtpHost",
            kind = FieldKind.HOST,
            required = true,
            hintKey = "emailHintHostExample",
        ),
        FieldSpec(
            key = "smtpPort",
            labelKey = "smtpPort",
            kind = FieldKind.NUMBER,
            required = true,
            defaultValue = DEFAULT_PORT.toString(),
            hintKey = "emailHintPort",
        ),
        FieldSpec(
            key = "useSSL",
            labelKey = "useSSL",
            kind = FieldKind.SWITCH,
            defaultValue = DEFAULT_USE_SSL.toString(),
        ),
        FieldSpec(
            key = "username",
            labelKey = "smtpAccount",
            kind = FieldKind.EMAIL_ADDRESS,
            required = true,
            hintKey = "emailHintAddressExample",
        ),
        FieldSpec(
            key = "password",
            labelKey = "smtpPassword",
            kind = FieldKind.SECRET,
            required = true,
            hintKey = "emailHintPassword",
        ),
        FieldSpec(
            key = "fromEmail",
            labelKey = "fromEmail",
            kind = FieldKind.EMAIL_ADDRESS,
            required = true,
            hintKey = "emailHintAddressExample",
        ),
        FieldSpec(
            key = "toEmail",
            labelKey = "toEmail",
            required = true,
            hintKey = "emailHintRecipients",
        ),
        FieldSpec(
            key = "subjectTemplate",
            labelKey = "subjectTemplate",
            hintKey = "emailHintSubject",
            presets = listOf(
                FieldPreset("presetDefault", "emailPresetSubjectDefault"),
                FieldPreset("presetSimple", "emailPresetSubjectSimple"),
                FieldPreset("presetDetailed", "emailPresetSubjectDetailed"),
                FieldPreset("presetTime", "emailPresetSubjectTime"),
                FieldPreset("presetCode", "emailPresetSubjectCode"),
                FieldPreset("presetDevice", "emailPresetSubjectDevice"),
            ),
        ),
        FieldSpec(
            key = "bodyTemplate",
            labelKey = "bodyTemplate",
            kind = FieldKind.MULTILINE,
            hintKey = "emailHintBody",
            presets = listOf(
                // 「默认」= 清空自定义，把正文交回 `EmailSender.buildEmailBody` 的运行时默认。
                // valueKey=null 是显式语义，不是漏填词条。
                FieldPreset("presetDefault"),
                FieldPreset("presetStandard", "emailPresetBodyStandard"),
                FieldPreset("presetComplete", "emailPresetBodyComplete"),
                FieldPreset("presetCode", "emailPresetBodyCode"),
                FieldPreset("presetMinimal", "emailPresetBodyMinimal"),
            ),
        ),
    )

    fun descriptor(): Map<String, Any?> = mapOf(
        "family" to FAMILY,
        "key" to KEY,
        // nativeType 是 webhook/应用通道族跨进程身份（RetryQueue 持久化枚举名）。
        // 邮件没有这套身份（发送侧按 EmailConfig 走），**故意不发这个键** ——
        // 发一个等于造一个没人读的枚举名（extra_config 那类死键就是这么来的）。
        "labelKey" to "emailChannel",
        "iconKey" to KEY,
        // 邮件没有"官方基址"可识别：SMTP 主机由用户填，host 恒为空集
        // （非空集会被 Dart 的 URL 自动识别表要求逐一对齐）。
        "hosts" to emptyList<String>(),
        "capabilities" to listOf(
            Capability.SECRET_USED,
            Capability.SECRET_REQUIRED,
            Capability.SECRET_KEEPS_PREVIOUS,
            Capability.CUSTOM_TEMPLATE,
        ),
        "fields" to fields.map { it.toMap() },
    )

    fun descriptors(): List<Map<String, Any?>> = listOf(descriptor())
}
