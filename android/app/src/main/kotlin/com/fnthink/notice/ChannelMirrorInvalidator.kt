package com.fnthink.notice

import android.content.Context
import android.content.SharedPreferences

internal object ChannelMirrorInvalidator {
    private const val KEY_PENDING = "flutter.channel_mirror_invalidation_pending"

    internal val plainKeys = setOf(
        "flutter.webhook_channels",
        "flutter.webhook_urls",
        "flutter.webhook_url",
        "flutter.app_channels",
        "flutter.email_channels",
        "flutter.fnthink_channels",
        "flutter.fnthink_fanout_pending",
    )
    internal val secureKeys = setOf(
        "secure_webhook_channels",
        "secure_app_channels",
        "email_channel_passwords",
        "webhook_retry_queue",
    )

    private val invalidationLock = Any()

    private data class Store(
        val prefs: SharedPreferences,
        val keys: Set<String>,
    )

    private fun stores(context: Context): List<Store> = listOf(
        Store(
            context.getSharedPreferences(ConfigManager.FLUTTER_PREFS_NAME, Context.MODE_PRIVATE),
            plainKeys,
        ),
        Store(SecurePrefs.get(context), secureKeys),
        Store(context.getSharedPreferences("email_channel_configs", Context.MODE_PRIVATE), setOf("channels")),
        Store(context.getSharedPreferences("email_channel_passwords", Context.MODE_PRIVATE), setOf("passwords")),
    )

    fun isPending(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(ConfigManager.FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
            .getBoolean(KEY_PENDING, false)

    fun begin(context: Context): Boolean =
        context.applicationContext
            .getSharedPreferences(ConfigManager.FLUTTER_PREFS_NAME, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_PENDING, true)
            .commit()

    fun invalidate(context: Context): Boolean = synchronized(invalidationLock) {
        val appContext = context.applicationContext
        if (!SecurePrefs.isEncrypted(appContext)) return false
        val flutterPrefs = appContext.getSharedPreferences(
            ConfigManager.FLUTTER_PREFS_NAME,
            Context.MODE_PRIVATE,
        )
        return ChannelMirrorInvalidation.run(
            setPending = { pending ->
                flutterPrefs.edit().putBoolean(KEY_PENDING, pending).commit()
            },
            clear = {
                var succeeded = true
                for (store in stores(appContext)) {
                    val editor = store.prefs.edit()
                    for (key in store.keys) editor.remove(key)
                    succeeded = editor.commit() && succeeded
                }
                succeeded
            },
            verify = {
                stores(appContext).all { store ->
                    store.keys.all { key -> !store.prefs.contains(key) }
                }
            },
        )
    }
}
