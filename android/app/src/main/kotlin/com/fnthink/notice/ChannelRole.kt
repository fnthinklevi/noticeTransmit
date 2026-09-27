package com.fnthink.notice

/**
 * 通道的推送角色（roadmap T11/T12）。与 Dart 侧 `ChannelConfigCodec.normalizeRole` 同一套取值：
 * `primary` / `backup` / `unset` / `none`，**字符串常量，跨语言契约**（改任何一侧都要同步另一侧，
 * 由 ChannelRoutingContractTest 钉住）。
 *
 * 缺省与认不出的值都归 [PRIMARY]：
 *  - 老配置（v11 之前存的）本来就没有角色概念，语义等于"每条都推"；
 *  - 归成 [NONE] 会让一条通道从此静默收不到通知 —— 宁可多推，不可漏推。
 * ⚠ [UNSET] **不是**缺省值，只有"新建一条通道"这条路径会写它（1.5.76 反馈 #2：
 * 新建的不该默认算主，否则同一条通知会跟着全量重复推）。
 */
enum class ChannelRole {
    PRIMARY,
    BACKUP,

    /** 用户还没指定过主/备：有可用主时不推它，一条主都没设时照样推（不静默不发）。 */
    UNSET,

    /** 明确排除在推送之外（配置保留，随时可归队）。 */
    NONE,
    ;

    companion object {
        const val WIRE_PRIMARY = "primary"
        const val WIRE_BACKUP = "backup"
        const val WIRE_NONE = "none"
        const val WIRE_UNSET = "unset"

        fun parse(raw: String?): ChannelRole = when (raw?.trim()?.lowercase()) {
            WIRE_BACKUP -> BACKUP
            WIRE_NONE -> NONE
            WIRE_UNSET -> UNSET
            // null / "" / "tertiary" / 任何认不出的写法
            else -> PRIMARY
        }
    }
}
