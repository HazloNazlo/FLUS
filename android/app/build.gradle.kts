import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("key.properties")
val signing = Properties().apply { if (signingFile.exists()) signingFile.inputStream().use { load(it) } }

android {
    namespace = "com.openflux.launcher"
    compileSdk = 35
    ndkVersion = "27.0.12077973"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    defaultConfig {
        applicationId = "com.openflux.launcher"
        minSdk = 26
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        ndk { abiFilters.clear(); abiFilters.add("arm64-v8a") }
    }
    // Executable PIE is shipped as a native library so PackageManager extracts it
    // to read-only executable nativeLibraryDir, not the writable app data directory.
    packaging { jniLibs { useLegacyPackaging = true; keepDebugSymbols.add("**/libopenflux.so") } }
    signingConfigs {
        if (signingFile.exists()) {
            create("flusTest") {
                storeFile = file(signing.getProperty("storeFile"))
                storePassword = signing.getProperty("storePassword")
                keyAlias = signing.getProperty("keyAlias")
                keyPassword = signing.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        debug { applicationIdSuffix = ".debug" }
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            if (signingFile.exists()) signingConfig = signingConfigs.getByName("flusTest")
        }
    }
}

val verifyOpenFlux by tasks.registering {
    doLast {
        check(file("src/main/jniLibs/arm64-v8a/libopenflux.so").isFile) {
            "OpenFlux missing. Run bash scripts/build-core.sh from the project root."
        }
        if (gradle.startParameter.taskNames.any { it.contains("Release", ignoreCase = true) }) {
            check(signingFile.exists()) { "Release signing missing: configure android/key.properties (never commit keys)." }
        }
    }
}
tasks.named("preBuild").configure { dependsOn(verifyOpenFlux) }
flutter { source = "../.." }
dependencies { testImplementation("junit:junit:4.13.2") }
