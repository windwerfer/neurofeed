import java.util.Properties
import org.gradle.api.tasks.bundling.AbstractArchiveTask
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val useReleaseSigning = keystorePropertiesFile.exists()
if (useReleaseSigning) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
}

android {
    namespace = "org.windwerfer.neurofeed"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    signingConfigs {
        if (useReleaseSigning) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias", "release")
                keyPassword = keystoreProperties.getProperty("keyPassword", "")
                storeFile = file(keystoreProperties.getProperty("storeFile", ""))
                storePassword = keystoreProperties.getProperty("storePassword", "")
            }
        }
    }

    defaultConfig {
        applicationId = "org.windwerfer.neurofeed"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        ndk {
            abiFilters += listOf("arm64-v8a")
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            signingConfig =
                if (useReleaseSigning) {
                    signingConfigs.getByName("release")
                } else {
                    signingConfigs.getByName("debug")
                }
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }

    // Reproducible builds: AGP embeds a non-deterministic "Dependency Info"
    // block (id 0x504b4453) in the APK Signing Block unless disabled. It breaks
    // byte-identical rebuilds (see .ai/release.md).
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(JvmTarget.JVM_17)
    }
}

flutter {
    source = "../.."
}

// Reproducible archive output (fixed timestamps + deterministic ordering).
tasks.withType<AbstractArchiveTask>().configureEach {
    isPreserveFileTimestamps = false
    isReproducibleFileOrder = true
}
