plugins {
    id("com.android.application")
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties
import java.io.FileInputStream

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.fnthink.notice"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        create("release") {
            val ksFile = System.getenv("KEYSTORE_FILE") ?: keystoreProperties.getProperty("storeFile", "")
            val ksPassword = System.getenv("KEYSTORE_PASSWORD") ?: keystoreProperties.getProperty("storePassword", "")
            val ksAlias = System.getenv("KEY_ALIAS") ?: keystoreProperties.getProperty("keyAlias", "")
            val ksKeyPassword = System.getenv("KEY_PASSWORD") ?: keystoreProperties.getProperty("keyPassword", "")
            
            if (ksFile.isNotEmpty() && ksPassword.isNotEmpty() && ksAlias.isNotEmpty() && ksKeyPassword.isNotEmpty()) {
                storeFile = file(ksFile)
                storePassword = ksPassword
                keyAlias = ksAlias
                keyPassword = ksKeyPassword
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_21
        targetCompatibility = JavaVersion.VERSION_21
    }

    defaultConfig {
        applicationId = "com.fnthink.notice"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        println("DEBUG: flutter.versionName=${flutter.versionName}, flutter.versionCode=${flutter.versionCode}")
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk {
            abiFilters += listOf("arm64-v8a")
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
        jniLibs {
            excludes += listOf(
                "lib/armeabi/**",
                "lib/armeabi-v7a/**",
                "lib/x86/**",
                "lib/x86_64/**",
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
}

flutter {
    source = "../.."
}
