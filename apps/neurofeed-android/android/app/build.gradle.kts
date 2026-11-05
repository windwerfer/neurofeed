import com.android.build.api.variant.FilterConfiguration

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val repoRoot = rootDir.resolve("../../..").canonicalFile
val abiList = (findProperty("abis") as String).split(",").map { it.trim() }.filter { it.isNotEmpty() }

/**
 * Version name: `-PversionName=…` > scripts/version.sh ($NEUROFEED_VERSION > git tag on/before
 * HEAD > Cargo.toml). Base versionCode from its X.Y.Z: X*10000 + Y*100 + Z (Y, Z < 100).
 */
val verName = (findProperty("versionName") as String?)?.removePrefix("v")
    ?: providers.exec { commandLine(repoRoot.resolve("scripts/version.sh").path) }
        .standardOutput.asText.get().trim()
val verCode = Regex("""^(\d+)\.(\d+)\.(\d+)""").find(verName)?.destructured
    ?.let { (a, b, c) -> (a.toInt() * 10000 + b.toInt() * 100 + c.toInt()).coerceAtLeast(1) }
    ?: error("version '$verName' does not start with X.Y.Z")

/**
 * Per-ABI versionCode (docs/release.md): `base * 10 + abiDigit`, base = X*10000+Y*100+Z.
 * arm64 > armv7 so a 64-bit device that can run both always gets arm64 (F-Droid /
 * Play convention). 0 is the universal APK (debug builds without splits).
 */
val abiDigit = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86" to 3, "x86_64" to 4)

/**
 * Release signing from env (CI decodes KEYSTORE_BASE64 into NF_KEYSTORE). Unset = the
 * release APK stays unsigned (push CI, F-Droid builds and signs itself).
 */
val ksFile = System.getenv("NF_KEYSTORE")?.takeIf { it.isNotBlank() }?.let { file(it) }

android {
    namespace = "org.neurofeed.android"
    compileSdk = 35
    ndkVersion = "27.2.12479018"

    defaultConfig {
        applicationId = findProperty("appId") as String
        minSdk = 26
        targetSdk = 35
        versionCode = verCode
        versionName = verName
    }

    signingConfigs {
        if (ksFile != null) {
            create("release") {
                storeFile = ksFile
                storePassword = System.getenv("NF_KEYSTORE_PASSWORD")
                keyAlias = System.getenv("NF_KEY_ALIAS")
                keyPassword = System.getenv("NF_KEY_PASSWORD")
                enableV1Signing = false // minSdk 26: v2 + v3 are enough
                enableV2Signing = true
                enableV3Signing = true
            }
        }
    }

    // One APK per ABI (half the size of a fat APK); no universal APK.
    splits {
        abi {
            isEnable = true
            reset()
            include(*abiList.toTypedArray())
            isUniversalApk = false
        }
    }

    buildTypes {
        // Debug installs next to the release build (org.windwerfer.neurofeed.rs.debug).
        debug {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
        release {
            if (ksFile != null) signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    // F-Droid / reproducible builds: no Google-signed dependency blob in the APK.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }
    packaging { jniLibs.useLegacyPackaging = false }
}

androidComponents {
    onVariants { variant ->
        variant.outputs.forEach { out ->
            val abi = out.filters.find { it.filterType == FilterConfiguration.FilterType.ABI }?.identifier
            out.versionCode.set(verCode * 10 + (abi?.let { abiDigit[it] } ?: 0))
        }
    }
}

dependencies {
    implementation("androidx.games:games-activity:4.4.0")
    implementation("androidx.appcompat:appcompat:1.7.0")
    implementation("androidx.core:core-ktx:1.13.1")
}

/**
 * Build libneurofeed.so for every ABI with cargo-ndk into src/main/jniLibs.
 * The Rust side is always built optimized (debug egui is too slow on phones
 * and the unstripped .so would be huge); `-PrustDebug` opts out.
 */
fun cargoTask(name: String, release: Boolean) = tasks.register<Exec>(name) {
    workingDir = repoRoot
    environment("NEUROFEED_VERSION", verName) // nf_core::APP_VERSION in the .so
    val args = mutableListOf("cargo", "ndk", "-P", "26", "-o", file("src/main/jniLibs").path)
    abiList.forEach { args += listOf("-t", it) }
    args += listOf("build", "-p", "neurofeed-android")
    if (release) args += "--release"
    commandLine(args)
}
val cargoDebug = cargoTask("cargoBuildDebug", !hasProperty("rustDebug"))
val cargoRelease = cargoTask("cargoBuildRelease", true)
tasks.matching { it.name == "mergeDebugJniLibFolders" }.configureEach { dependsOn(cargoDebug) }
tasks.matching { it.name == "mergeReleaseJniLibFolders" }.configureEach { dependsOn(cargoRelease) }
