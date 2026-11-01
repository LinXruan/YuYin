import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// 读取 release 签名配置（android/key.properties 不提交到仓库）
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.debug.yuyin"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.debug.yuyin"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // 当构建参数指定单架构 android-arm64 时，精准过滤仅打包 arm64-v8a 原生库（剔除第三方库的 v7a/x86 冗余）
        val targetPlatform = project.findProperty("target-platform") as? String
        if (targetPlatform == "android-arm64") {
            ndk {
                abiFilters.clear()
                abiFilters.add("arm64-v8a")
            }
        }
    }

    signingConfigs {
        create("release") {
            // 使用独立的 release 私钥（android/app/yuyin-release.jks）
            if (keystorePropertiesFile.exists()) {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // release 使用单独的签名，不再复用 debug keystore
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

androidComponents {
    // release 使用独立包名，可与 debug 版同时安装
    onVariants(selector().withBuildType("release")) { variant ->
        variant.applicationId.set("com.release.yuyin")
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("androidx.documentfile:documentfile:1.0.1")
}

// 自动生成规范命名的 APK 文件副本 (YuYin_<version>_v8a.apk / Universal / debug)
val cleanVersionName = (flutter.versionName ?: "1.0.0").substringBefore('+')

tasks.matching { it.name.startsWith("assemble") }.configureEach {
    doLast {
        val targetPlatform = project.findProperty("target-platform") as? String
        val isArm64Only = targetPlatform == "android-arm64"
        val apkOutputDir = layout.buildDirectory.dir("outputs/apk").get().asFile

        if (name.contains("Release", ignoreCase = true)) {
            val releaseDir = File(apkOutputDir, "release")
            val rawReleaseApk = File(releaseDir, "app-release.apk")
            if (rawReleaseApk.exists()) {
                val customName = if (isArm64Only) "YuYin_${cleanVersionName}_v8a.apk" else "YuYin_${cleanVersionName}_Universal.apk"
                rawReleaseApk.copyTo(File(releaseDir, customName), overwrite = true)
            }
        }

        if (name.contains("Debug", ignoreCase = true)) {
            val debugDir = File(apkOutputDir, "debug")
            val rawDebugApk = File(debugDir, "app-debug.apk")
            if (rawDebugApk.exists()) {
                val customName = "YuYin_${cleanVersionName}_debug.apk"
                rawDebugApk.copyTo(File(debugDir, customName), overwrite = true)
            }
        }
    }
}
