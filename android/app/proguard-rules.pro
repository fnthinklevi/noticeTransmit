-keep class io.flutter.** { *; }
-keep class com.fnthink.notice.** { *; }

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