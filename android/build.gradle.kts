// 仓库顺序按环境切换（v1.62）：CI（GitHub Actions 境外 runner）必须上游优先——
// aliyun 镜像在境外慢且会返回 502，而 Gradle 一旦因错误把某个仓库标记为 disabled，
// 本轮依赖解析就整体失败（实测事故：com.sun.mail:android-mail 502 → androidx.test:* 连带全崩，
// 报 "Repository maven is disabled due to earlier error"）。本地开发在国内网络下反过来：
// 镜像优先，直连 google()/mavenCentral() 常超时。判据用 CI 环境变量，无需新增配置项。
// getenv 在变量缺失时返回 null：字面量作接收者，避免本地构建（无 CI）NPE
val useUpstreamFirst = "true".equals(System.getenv("CI"), ignoreCase = true)

// 引擎构件仓库也按环境切换：国内走 flutter-io.cn 镜像，CI 上未设该变量则回落到上游。
// 写死 googleapis 会让 FLUTTER_STORAGE_BASE_URL 失效（本机直连被拒 → 解析整体失败）。
val flutterStorageBaseUrl =
    System.getenv("FLUTTER_STORAGE_BASE_URL")?.trimEnd('/')
        ?: "https://storage.googleapis.com"

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
        maven{ url=uri("$flutterStorageBaseUrl/download.flutter.io")}
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


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
