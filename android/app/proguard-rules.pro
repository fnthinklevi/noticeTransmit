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

-keepattributes Signature
-keepattributes *Annotation*