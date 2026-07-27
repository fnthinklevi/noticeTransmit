import java.util.Properties

plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.fnthink.notice"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            // 1) CI：优先从环境变量读取（由 GitHub Actions secrets 在构建时注入，日志自动脱敏）
            val envStoreFile: String? = System.getenv("KEYSTORE_FILE")
            val envStorePassword: String? = System.getenv("KEYSTORE_PASSWORD")
            val envKeyAlias: String? = System.getenv("KEY_ALIAS")
            val envKeyPassword: String? = System.getenv("KEY_PASSWORD")

            // 2) 本地开发：从被 .gitignore 忽略的 android/key.properties 读取（绝不进版本库）
            val keyPropsFile = rootProject.file("key.properties")
            val props = Properties()
            if (keyPropsFile.exists()) {
                props.load(keyPropsFile.inputStream())
            }
            val propsStoreFile = props.getProperty("storeFile")
            val propsStorePassword = props.getProperty("storePassword")
            val propsKeyAlias = props.getProperty("keyAlias")
            val propsKeyPassword = props.getProperty("keyPassword")

            // 3) 合并：环境变量优先，其次 key.properties
            val finalStoreFile = envStoreFile ?: propsStoreFile
            val finalStorePassword = envStorePassword ?: propsStorePassword
            val finalKeyAlias = envKeyAlias ?: propsKeyAlias
            val finalKeyPassword = envKeyPassword ?: propsKeyPassword

            // 4) 任一缺失都明确失败，绝不回退到源码中写死的密码
            if (finalStoreFile != null && finalStorePassword != null &&
                finalKeyAlias != null && finalKeyPassword != null) {
                storeFile = file(finalStoreFile)
                storePassword = finalStorePassword
                keyAlias = finalKeyAlias
                keyPassword = finalKeyPassword
            } else {
                throw GradleException(
                    "未找到发布签名配置，构建已中止。请二选一：\n" +
                    "  · 本地：在 android/key.properties 中填写 storeFile / storePassword / keyAlias / keyPassword（该文件已被 .gitignore 忽略）；\n" +
                    "  · CI：设置环境变量 KEYSTORE_FILE / KEYSTORE_PASSWORD / KEY_ALIAS / KEY_PASSWORD。\n" +
                    "禁止将任何密钥明文写入被 git 跟踪的源文件。"
                )
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.fnthink.notice"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 按 Flutter --target-platform 动态设置 ABI 过滤
        // 单架构包必须纯净，只含一种 .so，不得混入其他架构的第三方库！
        // 检测优先级：环境变量 > Flutter Gradle 属性 > 多架构回退
        ndk {
            abiFilters.clear()
            val envTarget = System.getenv("FLUTTER_TARGET_PLATFORM")
            val flutterTarget = project.findProperty("flutter.targetPlatform") as? String
            val targetPlatform = envTarget ?: flutterTarget ?: ""
            when {
                targetPlatform.contains("arm64") && !targetPlatform.contains(",") -> {
                    abiFilters.add("arm64-v8a")
                    println("[abiFilter] 单架构 arm64-v8a")
                }
                targetPlatform.contains("x64") && !targetPlatform.contains(",") -> {
                    abiFilters.add("x86_64")
                    println("[abiFilter] 单架构 x86_64")
                }
                targetPlatform.contains("arm") && !targetPlatform.contains("arm64") && !targetPlatform.contains(",") -> {
                    abiFilters.add("armeabi-v7a")
                    println("[abiFilter] 单架构 armeabi-v7a")
                }
                else -> {
                    abiFilters.add("arm64-v8a")
                    abiFilters.add("armeabi-v7a")
                    abiFilters.add("x86_64")
                    println("[abiFilter] 融合包（全架构）")
                }
            }
        }
    }

    buildTypes {
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = signingConfigs.getByName("release")
        }
    }

    packaging {
        resources {
            excludes += setOf(
                "META-INF/NOTICE.md",
                "META-INF/LICENSE.md",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_21
    }
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    implementation("com.tencent.bugly:crashreport:4.1.9.3")
    implementation("com.sun.mail:android-mail:1.6.7")
    implementation("com.sun.mail:android-activation:1.6.7")
}

flutter {
    source = "../.."
}
