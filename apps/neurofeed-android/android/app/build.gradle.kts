plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

val repoRoot = rootDir.resolve("../../..").canonicalFile
val abiList = (findProperty("abis") as String).split(",").map { it.trim() }.filter { it.isNotEmpty() }

/** Version from the newest git tag (`X.Y.Z` or `vX.Y.Z`); 0.1.0 when untagged. */
fun gitVersion(): Pair<String, Int> {
    val tag = try {
        providers.exec {
            commandLine("git", "-C", repoRoot.path, "describe", "--tags", "--abbrev=0", "--match", "[v0-9]*")
            isIgnoreExitValue = true
        }.standardOutput.asText.get().trim()
    } catch (e: Exception) { "" }
    val m = Regex("""^v?(\d+)\.(\d+)\.(\d+)""").find(tag) ?: return "0.1.0" to 100
    val (a, b, c) = m.destructured
    return "$a.$b.$c" to (a.toInt() * 10000 + b.toInt() * 100 + c.toInt()).coerceAtLeast(1)
}
val (verName, verCode) = gitVersion()

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
        ndk { abiFilters += abiList }
    }

    buildTypes {
        release {
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
