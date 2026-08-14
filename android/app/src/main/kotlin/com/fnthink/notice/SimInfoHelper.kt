package com.fnthink.notice

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.telephony.SubscriptionInfo
import android.telephony.SubscriptionManager
import android.telephony.TelephonyManager
import android.util.Log

/**
 * SIM 卡信息识别助手
 *
 * 解决问题：双卡场景下识别不稳定（有时能识别，有时不能）。
 *
 * 多策略降级链：
 * 1. Intent extras 中的 subscriptionId（兼容多种 key：subscription / EXTRA_SUBSCRIPTION_ID）
 * 2. SubscriptionManager 精确匹配 subId
 * 3. 单卡场景回退到唯一卡
 * 4. 默认语音 SIM 回退（双卡场景：PHONE_STATE 广播通常不携带 subscriptionId）
 * 5. slotIndex 反查（SubscriptionManager.getSlotIndex 在公共 SDK 中不可见，已禁用）
 * 6. 占位回退 —— 权限缺失或无信息时的兜底
 *
 * 缓存：activeSubscriptionInfoList 缓存 60 秒，避免每次广播都查
 * 权限：READ_PHONE_STATE 缺失时不抛异常，回退占位标签
 */
object SimInfoHelper {
    private const val TAG = "SimInfoHelper"
    private const val CACHE_TTL_MS = 60_000L // 60 秒缓存

    @Volatile
    private var cachedSubs: List<SubscriptionInfo>? = null
    @Volatile
    private var cachedAt: Long = 0L

    data class SimInfo(
        val subscriptionId: Int,
        val slotIndex: Int,        // 0-based
        val carrierName: String,
        val displayLabel: String   // "卡1(中国移动)" / "SIM1(China Mobile)" 等
    )

    /**
     * 从 Intent 中提取 SIM 信息（SMS_RECEIVED / PHONE_STATE 通用入口）
     * 兼容多种 key：subscription / subId / EXTRA_SUBSCRIPTION_ID
     */
    fun getSimInfoFromIntent(context: Context, intent: Intent?): SimInfo? {
        if (intent == null) return null
        var subId = -1

        // 策略 1：从 Intent extras 提取 subscriptionId
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP_MR1) {
            subId = intent.getIntExtra("subscription", -1)
            if (subId <= 0) {
                // 部分厂商用 EXTRA_SUBSCRIPTION_ID（API 29+）
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    subId = intent.getIntExtra(TelephonyManager.EXTRA_SUBSCRIPTION_ID, -1)
                }
            }
            if (subId <= 0) {
                subId = intent.getIntExtra("subId", -1)
            }
        }

        // 策略 2：subId 精确匹配
        if (subId > 0) {
            getSimInfoBySubId(context, subId)?.let { return it }
        }

        // 策略 3：单卡回退（无 subId 且只有一张卡时，归属唯一卡）
        val activeSubs = getActiveSubscriptions(context)
        if (subId <= 0 && activeSubs.size == 1) {
            return buildSimInfo(activeSubs[0])
        }

        // 策略 4：默认语音 SIM 回退（双卡场景：PHONE_STATE 广播通常不携带 subscriptionId，
        //         用系统默认语音通话 SIM 作为合理推断）
        // 注意：getDefaultVoiceSubscriptionId() 为 API 24+ 方法，老系统直接调用会抛
        //       NoSuchMethodError（属 Error，catch(Exception) 接不住导致进程崩溃），必须按版本判断。
        if (subId <= 0 && activeSubs.size > 1 && Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            val defaultVoiceSubId = SubscriptionManager.getDefaultVoiceSubscriptionId()
            if (defaultVoiceSubId > 0) {
                activeSubs.find { it.subscriptionId == defaultVoiceSubId }?.let { return buildSimInfo(it) }
            }
        }

        // 策略 5：subId > 0 但精确匹配失败 → 尝试用 slotIndex 查
        // 说明：SubscriptionManager.getSlotIndex(int subId) 在公共 SDK 中不可见
        //       （被标记为 @SystemApi/@hide，仅系统应用可用），无法直接调用。
        //       该场景实际触发率极低（subId 不在 activeSubs 中且非单卡），直接走策略 6 占位回退。

        // 策略 6：占位回退（权限拒绝或无信息）
        return null
    }

    /**
     * 根据 subscriptionId 获取 SIM 信息
     */
    fun getSimInfoBySubId(context: Context, subscriptionId: Int): SimInfo? {
        if (subscriptionId <= 0) return null
        val activeSubs = getActiveSubscriptions(context)

        // 精确匹配
        activeSubs.find { it.subscriptionId == subscriptionId }?.let { return buildSimInfo(it) }

        // 单卡回退
        if (activeSubs.size == 1) return buildSimInfo(activeSubs[0])

        // subId 不在活跃列表中 → 无法在公共 SDK 中反查 slotIndex（getSlotIndex 不可见）
        // 直接返回 null，由调用方走占位回退

        return null
    }

    /**
     * 兼容旧接口：返回 display label 字符串（"卡N(运营商)"），找不到时返回 null
     */
    fun getSimLabel(context: Context, subscriptionId: Int): String? {
        return getSimInfoBySubId(context, subscriptionId)?.displayLabel
    }

    /**
     * 从 Intent 直接获取 label（兼容旧调用方式）
     */
    fun getSimLabelFromIntent(context: Context, intent: Intent?): String? {
        return getSimInfoFromIntent(context, intent)?.displayLabel
    }

    // ========== 内部实现 ==========

    private fun getActiveSubscriptions(context: Context): List<SubscriptionInfo> {
        // 命中缓存
        val now = System.currentTimeMillis()
        cachedSubs?.let {
            if (now - cachedAt < CACHE_TTL_MS) return it
        }

        // 权限检查：无权限时不缓存空列表（缓存会掩盖运行时授权后的变化，
        // 导致授权后最长 60 秒内 SIM 识别仍全部为空）
        if (!hasReadPhoneStatePermission(context)) {
            Log.w(TAG, "READ_PHONE_STATE not granted, returning empty subscription list")
            return emptyList()
        }

        return try {
            val sm = context.getSystemService(Context.TELEPHONY_SUBSCRIPTION_SERVICE) as? SubscriptionManager
            if (sm == null) {
                cachedSubs = emptyList()
                cachedAt = now
                return emptyList()
            }
            val list = sm.activeSubscriptionInfoList ?: emptyList()
            cachedSubs = list
            cachedAt = now
            list
        } catch (e: SecurityException) {
            Log.w(TAG, "SecurityException reading subscriptions: ${e.message}")
            cachedSubs = emptyList()
            cachedAt = now
            emptyList()
        } catch (e: Exception) {
            Log.e(TAG, "Failed to read active subscriptions", e)
            cachedSubs = emptyList()
            cachedAt = now
            emptyList()
        }
    }

    private fun buildSimInfo(info: SubscriptionInfo): SimInfo {
        val slot = info.simSlotIndex + 1 // 0-based → 1-based
        val carrier = info.carrierName?.toString()?.takeIf { it.isNotEmpty() }
            ?: info.displayName?.toString()?.takeIf { it.isNotEmpty() }
            ?: "SIM"
        // 中英双语（跟随应用语言设置）：中文 "卡1(中国移动)" / 英文 "SIM1(China Mobile)"
        val label = "${I18n.simSlotLabel(slot)}($carrier)"
        return SimInfo(
            subscriptionId = info.subscriptionId,
            slotIndex = info.simSlotIndex,
            carrierName = carrier,
            displayLabel = label
        )
    }

    private fun hasReadPhoneStatePermission(context: Context): Boolean {
        return try {
            context.checkPermission(
                android.Manifest.permission.READ_PHONE_STATE,
                android.os.Process.myPid(),
                android.os.Process.myUid()
            ) == PackageManager.PERMISSION_GRANTED
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 清空缓存（配置变更后调用）
     */
    fun invalidateCache() {
        cachedSubs = null
        cachedAt = 0L
    }
}
