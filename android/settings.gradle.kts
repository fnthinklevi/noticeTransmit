
pluginManagement {
    // 仓库顺序按环境切换（v1.62）：CI（GitHub Actions 境外 runner）必须上游优先——
    // aliyun 镜像在境外慢且会 502，而 Gradle 一旦因错误把某仓库标记为 disabled，本轮解析
    // 就整体失败（实测：com.sun.mail:android-mail 502 → androidx.test:* 连带全崩，
    // 报 "Repository maven is disabled due to earlier error"）。本地国内网络反之：镜像优先。
    // ⚠ 必须写在 pluginManagement 内部——它是独立编译阶段，看不到脚本顶层的 val。
    // getenv 变量缺失时返回 null：字面量作接收者，避免本地构建（无 CI）NPE
    val useUpstreamFirst = "true".equals(System.getenv("CI"), ignoreCase = true)

    // 引擎构件仓库同样按环境切换：国内走 flutter-io.cn 镜像（storage.googleapis.com 在本机
    // 直连被拒），CI 上未设该变量则回落到上游。写死字面量会让镜像变量失效——Flutter 插件
    // 虽然也按 env 注册了仓库，但只要存量的 googleapis 仓库在场，解析失败就整体失败。
    val flutterStorageBaseUrl =
        System.getenv("FLUTTER_STORAGE_BASE_URL")?.trimEnd('/')
            ?: "https://storage.googleapis.com"

    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            file("local.properties").inputStream().use { properties.load(it) }
            val flutterSdkPath = properties.getProperty("flutter.sdk")
            require(flutterSdkPath != null) { "flutter.sdk not set in local.properties" }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        if (useUpstreamFirst) {
            google()
            mavenCentral()
            gradlePluginPortal()
        }
        maven{ url=uri("https://maven.aliyun.com/repository/releases")}
        maven{ url=uri("https://maven.aliyun.com/repository/google")}
        maven{ url=uri("https://maven.aliyun.com/repository/central")}
        maven{ url=uri("https://maven.aliyun.com/repository/gradle-plugin")}
        maven{ url=uri("https://maven.aliyun.com/repository/public")}
        maven{ url=uri("https://maven.aliyun.com/repository/snapshots")}
        maven{ url=uri("https://jitpack.io")}
        maven{ url=uri("$flutterStorageBaseUrl/download.flutter.io")}
        if (!useUpstreamFirst) {
            google()
            mavenCentral()
            gradlePluginPortal()
        }
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "9.3.0" apply false
    id("org.jetbrains.kotlin.android") version "2.3.20" apply false
}

include(":app")
