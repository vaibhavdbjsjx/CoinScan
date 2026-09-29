import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()

if (hasReleaseKeystore) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.coinvault.coinvault_ai"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.coinvault.coinvault_ai"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (hasReleaseKeystore) {
                val storeFilePath = keystoreProperties.getProperty("storeFile")
                val storePass = keystoreProperties.getProperty("storePassword")
                val keyAl = keystoreProperties.getProperty("keyAlias")
                val keyPass = keystoreProperties.getProperty("keyPassword")

                if (storeFilePath != null && storePass != null && keyAl != null && keyPass != null) {
                    storeFile = rootProject.file(storeFilePath)
                    storePassword = storePass
                    keyAlias = keyAl
                    keyPassword = keyPass
                }
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseKeystore &&
                keystoreProperties.getProperty("storeFile") != null &&
                rootProject.file(keystoreProperties.getProperty("storeFile")).exists()) {
                signingConfig = signingConfigs.getByName("release")
            } else {
                // Strict production security: NEVER fall back to debug signing.
                // Fail if strict production release signing is enforced, otherwise produce unsigned.
                val enforceSigning = project.hasProperty("requireReleaseSigning") ||
                    System.getenv("REQUIRE_RELEASE_SIGNING") == "true"
                if (enforceSigning) {
                    throw GradleException(
                        "Production release signing is not configured.\n" +
                        "Provide android/key.properties and the production upload keystore.\n" +
                        "See android/key.properties.example for setup instructions."
                    )
                }
                signingConfig = null
            }
        }
    }
}

// Build-time safety validation: guarantee debug signing can NEVER be applied to release build
gradle.taskGraph.whenReady {
    allTasks.forEach { task ->
        if (task.name.contains("Release", ignoreCase = true) && task.project.name == "app") {
            val releaseType = android.buildTypes.getByName("release")
            if (releaseType.signingConfig == android.signingConfigs.getByName("debug")) {
                throw GradleException(
                    "FATAL SECURITY VIOLATION: Release build is configured to use debug signing!\n" +
                    "Production builds must use a dedicated upload keystore via android/key.properties."
                )
            }
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
