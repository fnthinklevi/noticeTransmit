# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Flutter Embedding
-keep class io.flutter.embedding.** { *; }

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase

# Notification Listener Service
-keep class com.fnthink.notice.NotificationMonitorService { *; }
-keep class com.fnthink.notice.SmsReceiver { *; }
-keep class com.fnthink.notice.PhoneCallReceiver { *; }
-keep class com.fnthink.notice.BootReceiver { *; }
-keep class com.fnthink.notice.WebhookPayloadBuilder { *; }
-keep class com.fnthink.notice.PrefsHelper { *; }

# MethodChannel
-keep class com.fnthink.notice.MainActivity { *; }

# Kotlin
-dontwarn kotlin.**
-keep class kotlin.** { *; }
-keep class kotlin.Metadata { *; }

# Play Core (Flutter references but not used)
-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }
