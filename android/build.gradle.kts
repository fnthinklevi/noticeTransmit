// 仓库顺序按环境切换（v1.62）：CI（GitHub Actions 境外 runner）必须上游优先——
// aliyun 镜像在境外慢且会返回 502，而 Gradle 一旦因错误把某个仓库标记为 disabled，
// 本轮依赖解析就整体失败（实测事故：com.sun.mail:android-mail 502 → androidx.test:* 连带全崩，
// 报 "Repository maven is disabled due to earlier error"）。本地开发在国内网络下反过来：
// 镜像优先，直连 google()/mavenCentral() 常超时。判据用 CI 环境变量，无需新增配置项。
// getenv 在变量缺失时返回 null：字面量作接收者，避免本地构建（无 CI）NPE
val useUpstreamFirst = "true".equals(System.getenv("CI"), ignoreCase = true)

allprojects {
    repositories {
        if (useUpstreamFirst) {
            google()
            mavenCentral()
        }
        maven{ url=uri("https://maven.aliyun.com/repository/releases")}
        maven{ url=uri("https://maven.aliyun.com/repository/google")}
        maven{ url=uri("https://maven.aliyun.com/repository/central")}
        maven{ url=uri("https://maven.aliyun.com/repository/gradle-plugin")}
        maven{ url=uri("https://maven.aliyun.com/repository/public")}
        maven{ url=uri("https://maven.aliyun.com/repository/snapshots")}
        maven{ url=uri("https://jitpack.io")}
        maven{ url=uri("https://storage.googleapis.com/download.flutter.io")}
        if (!useUpstreamFirst) {
            google()
            mavenCentral()
        }
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
