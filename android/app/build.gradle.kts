plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

import java.util.Properties

android {
    // namespace 必须是合法 Java 包名(段不能以数字开头);
    // applicationId(安装包标识)则使用用户指定的 top.17ued.tts。
    namespace = "top.ued17.tts"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        // 存在 android/key.properties(含正式 keystore 信息)时启用 release 签名;
        // 否则不创建,release 构建回退 debug 签名,保证本地/CI 可构建。
        val keystorePropsFile = rootProject.file("key.properties")
        if (keystorePropsFile.exists()) {
            val props = Properties().apply {
                load(keystorePropsFile.inputStream())
            }
            create("release") {
                storeFile = file(props.getProperty("storeFile"))
                storePassword = props.getProperty("storePassword")
                keyAlias = props.getProperty("keyAlias")
                keyPassword = props.getProperty("keyPassword")
            }
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        // 注:top.17ued.tts 不符合 Android 包名规则(段不能以数字开头),使用 top.ued17.tts。
        applicationId = "top.ued17.tts"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // record 7.x 要求 minSdk ≥ 23(语音对话/克隆用麦克风)。
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // ── Patrol 集成测试 ────────────────────────────────────────────
        testInstrumentationRunner = "pl.leancode.patrol.PatrolJUnitRunner"
        testInstrumentationRunnerArguments["clearPackageData"] = "true"
    }

    testOptions {
        execution = "ANDROIDX_TEST_ORCHESTRATOR"
    }

    buildTypes {
        release {
            // 配置了 android/key.properties 时用正式签名,否则回退 debug 签名。
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
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
    // ── Patrol 集成测试 ───────────────────────────────────────────────
    androidTestUtil("androidx.test:orchestrator:1.4.2")
    // runner 版本须与主 classpath 的 consistent resolution 约束一致(1.5.1)。
    androidTestImplementation("androidx.test:runner:1.5.1")
    androidTestImplementation("androidx.test:rules:1.5.0")
    androidTestImplementation("junit:junit:4.13.2")
}
