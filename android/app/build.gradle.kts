import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import org.jetbrains.kotlin.konan.properties.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val agpMajorVersion = com.android.Version.ANDROID_GRADLE_PLUGIN_VERSION
    .substringBefore('.')
    .toInt()
val builtInKotlinProperty = providers.gradleProperty("android.builtInKotlin").orNull
val isBuiltInKotlinEnabled = agpMajorVersion >= 9 &&
        (builtInKotlinProperty == null || builtInKotlinProperty.toBoolean())
if (!isBuiltInKotlinEnabled) {
    apply(plugin = "org.jetbrains.kotlin.android")
}

val readingTest = providers.gradleProperty("readingTest")
    .map(String::toBoolean)
    .getOrElse(false)

android {
    namespace = "com.example.pilinara"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = if (readingTest) "com.bejukoro.pilinara.readingtest" else "com.bejukoro.pilinara"
        minSdk = flutter.minSdkVersion
        targetSdk = 37
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        providers.gradleProperty("forkReleaseAbi").orNull?.let { abi ->
            require(abi in setOf("arm64-v8a", "armeabi-v7a", "x86_64")) {
                "Unsupported forkReleaseAbi: $abi"
            }
            ndk.abiFilters.add(abi)
        }
    }

    packagingOptions {
        jniLibs {
            useLegacyPackaging = true
            providers.gradleProperty("forkReleaseAbi").orNull?.let { selected ->
                setOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
                    .filter { it != selected }
                    .forEach { excludes.add("**/$it/**") }
            }
        }
    }

    val keyProperties = Properties().also {
        val properties = rootProject.file("key.properties")
        if (properties.exists())
            it.load(properties.inputStream())
    }

    val config = keyProperties.getProperty("storeFile")?.let {
        signingConfigs.create("release") {
            storeFile = file(it)
            storePassword = keyProperties.getProperty("storePassword")
            keyAlias = keyProperties.getProperty("keyAlias")
            keyPassword = keyProperties.getProperty("keyPassword")
            enableV1Signing = true
            enableV2Signing = true
        }
    }

    buildFeatures {
        if (project.hasProperty("dev") || readingTest) {
            resValues = true
        }
    }

    buildTypes {
        all {
            signingConfig = if (name == "release") config else signingConfigs["debug"]
        }
        release {
            if (readingTest) {
                resValue("string", "app_name", "PiliNara 阅读测试")
                resValue("string", "shortcut_action", "com.bejukoro.pilinara.readingtest.SHORTCUT")
            }
            if (project.hasProperty("dev")) {
                applicationIdSuffix = ".dev"
                resValue(
                    type = "string",
                    name = "app_name",
                    value = "PiliNara Fork dev",
                )
            }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        debug {
            applicationIdSuffix = ".debug"
        }
    }

    gradle.taskGraph.whenReady {
        if (config == null && allTasks.any { it.path == ":app:packageRelease" || it.path == ":app:signReleaseBundle" }) {
            throw GradleException("Release signing is required. Configure android/key.properties before building a release.")
        }
    }

    applicationVariants.all {
        val variant = this
        variant.outputs.forEach { output ->
            (output as ApkVariantOutputImpl).versionCodeOverride = flutter.versionCode
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
