-keep class io.flutter.** { *; }
-keep class com.fnthink.notice.** { *; }

# 隐私保护：release 构建移除调试/信息级日志调用（R8 优化删除调用点）。
# 通知标题、短信内容、验证码、号码等敏感信息不得进 logcat——Bugly 崩溃上报
# 附带的日志也不会包含这些内容（详见 README「隐私说明」）。
# Log.w/e 保留用于排查错误，但不得输出敏感字段（代码审查把关）。
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}

-dontwarn okhttp3.**
-keep class okhttp3.** { *; }
-dontwarn okio.**
-keep class okio.** { *; }

-dontwarn com.google.android.play.core.**
-keep class com.google.android.play.core.** { *; }

# Bugly 崩溃统计
-dontwarn com.tencent.bugly.**
-keep class com.tencent.bugly.** { *; }
-keep public class com.tencent.bugly.**{*;}

# SQLCipher
-keep class net.sqlcipher.** { *; }
-keep class net.sqlcipher.database.** { *; }

# javax.mail (SMTP 邮件发送，依赖反射加载传输协议)
-dontwarn com.sun.mail.**
-dontwarn javax.mail.**
-dontwarn javax.activation.**
-keep class com.sun.mail.** { *; }
-keep class javax.mail.** { *; }
-keep class javax.activation.** { *; }
-keep class com.sun.mail.handlers.** { *; }
-keep class com.sun.mail.smtp.** { *; }
# WorkManager
-keep class androidx.work.** { *; }
-keep class net.jodah.concurrentunit.** { *; }
-dontwarn androidx.work.**

# 保留服务提供者配置文件
-keepnames class * extends javax.mail.Provider

-keepattributes Signature
-keepattributes *Annotation*