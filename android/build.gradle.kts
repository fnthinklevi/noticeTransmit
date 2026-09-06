allprojects {
    repositories {
        maven{ url=uri("https://maven.aliyun.com/repository/releases")}
        maven{ url=uri("https://maven.aliyun.com/repository/google")}
        maven{ url=uri("https://maven.aliyun.com/repository/central")}
        maven{ url=uri("https://maven.aliyun.com/repository/gradle-plugin")}
        maven{ url=uri("https://maven.aliyun.com/repository/public")}
        maven{ url=uri("https://maven.aliyun.com/repository/snapshots")}
        maven{ url=uri("https://jitpack.io")}
        maven{ url=uri("https://storage.googleapis.com/download.flutter.io")}
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker 8.x 自身 compileSdk 34，低于 flutter_plugin_android_lifecycle 要求的 36+，
// 强制其以 compileSdk 37 编译以通过 checkReleaseAarMetadata（升级 file_picker 大版本会与
// flutter_secure_storage 的 win32 版本冲突，故采用子项目 compileSdk 覆盖）。
subprojects {
    if (name == "file_picker") {
        afterEvaluate {
            extensions.findByType(com.android.build.gradle.LibraryExtension::class.java)?.apply {
                compileSdk = 37
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
