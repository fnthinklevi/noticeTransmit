package com.fnthink.notice

import android.content.Context
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.util.Log

/**
 * 双卡工具：根据 subscriptionId 获取 SIM 卡槽位索引和运营商名称
 * 返回格式：如 "卡1(中国移动)" / "卡2(中国电信)" / null（单卡或无信息）
 */
object SimInfoHelper {
    private const val TAG = "SimInfoHelper"

    /**
     * 根据 subscriptionId 获取 SIM 卡显示名称
     * @return "卡N(运营商)" 或 null
     */
    fun getSimLabel(context: Context, subscriptionId: Int): String? {
        if (subscriptionId <= 0) return null
        try {
            val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
                ?: return null
            val activeSubs = sm.activeSubscriptionInfoList ?: return null
            val info: SubscriptionInfo? = activeSubs.find { it.subscriptionId == subscriptionId }
            if (info != null) {
                val slot = info.simSlotIndex + 1 // 0-based → 1-based
                val carrier = info.carrierName?.toString()?.takeIf { it.isNotEmpty() } ?: "SIM"
                return "卡$slot($carrier)"
            }
            // 如果找不到，至少试试单卡逻辑
            if (activeSubs.size == 1) {
                val single = activeSubs[0]
                val slot = single.simSlotIndex + 1
                val carrier = single.carrierName?.toString()?.takeIf { it.isNotEmpty() } ?: "SIM"
                return "卡$slot($carrier)"
            }
        } catch (e: Exception) {
            Log.e(TAG, "获取SIM信息失败 subId=$subscriptionId", e)
        }
        return null
    }
}
