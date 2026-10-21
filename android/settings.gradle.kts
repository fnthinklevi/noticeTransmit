
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
    // AGP 9.4.1（2026-10 最新稳定）：⚠ 它内置的 Kotlin 仍是 kotlin-gradle-plugin 2.2.10，
    // 与 9.3.0 相同 ⇒ 升 AGP 不会抬高 Kotlin 版本，版本只由下面那行 classpath 钉决定。
    id("com.android.application") version "9.4.1" apply false
    // Kotlin 2.4.21（2026-10 最新稳定）：Flutter 3.47 的 warn 线是 2.3.20、error 线 2.2.20，
    // 官方模板给新项目的是 2.4.0。⚠ 这里 **只做 classpath 版本钉，不 apply**（`apply false`）：
    // 编译已交给 AGP 9 的内置 Kotlin，而 AGP 9.4.1 自带 KGP 仍是 2.2.10 —— 把 2.4.21 留在
    // classpath 上，Gradle 的版本冲突解析会把内置 Kotlin 用的那份抬到 2.4.21（AGP 对内置
    // Kotlin 只设下限 2.1.0，不设上限）。apply 的话就会重新触发 KGP 的弃用警告。
    id("org.jetbrains.kotlin.android") version "2.4.21" apply false
}

include(":app")
