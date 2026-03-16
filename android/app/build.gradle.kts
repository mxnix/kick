import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    val keystoreProperties = Properties().apply {
        val propertiesFile = rootProject.file("key.properties")
        if (propertiesFile.exists()) {
            load(FileInputStream(propertiesFile))
        }
    }
    fun releaseSigningValue(propertyName: String, environmentName: String): String? {
        val propertyValue = keystoreProperties.getProperty(propertyName)?.trim()
        if (!propertyValue.isNullOrEmpty()) {
            return propertyValue
        }
        val environmentValue = System.getenv(environmentName)?.trim()
        return if (environmentValue.isNullOrEmpty()) null else environmentValue
    }

    val releaseStoreFile = releaseSigningValue("storeFile", "KICK_ANDROID_KEYSTORE_PATH")
    val releaseStorePassword = releaseSigningValue(
        "storePassword",
        "KICK_ANDROID_KEYSTORE_PASSWORD"
    )
    val releaseKeyAlias = releaseSigningValue("keyAlias", "KICK_ANDROID_KEY_ALIAS")
    val releaseKeyPassword = releaseSigningValue("keyPassword", "KICK_ANDROID_KEY_PASSWORD")
    val hasReleaseSigning = !releaseStoreFile.isNullOrEmpty() &&
        !releaseStorePassword.isNullOrEmpty() &&
        !releaseKeyAlias.isNullOrEmpty() &&
        !releaseKeyPassword.isNullOrEmpty()

    namespace = "com.nikzmx.kick"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.nikzmx.kick"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigning) {
            create("release") {
                storeFile = file(releaseStoreFile!!)
                storePassword = releaseStorePassword
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
            }
        }
    }

    buildTypes {
        release {
            if (hasReleaseSigning) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

flutter {
    source = "../.."
}

val requestedTasks = gradle.startParameter.taskNames.joinToString(" ").lowercase()
val releaseTaskRequested = requestedTasks.contains("release") || requestedTasks.contains("bundle")
if (releaseTaskRequested) {
    val keyPropertiesFile = rootProject.file("key.properties")
    val hasKeyProperties = keyPropertiesFile.exists()
    val hasEnvironmentSigning = listOf(
        "KICK_ANDROID_KEYSTORE_PATH",
        "KICK_ANDROID_KEYSTORE_PASSWORD",
        "KICK_ANDROID_KEY_ALIAS",
        "KICK_ANDROID_KEY_PASSWORD",
    ).all { !System.getenv(it).isNullOrBlank() }
    if (!hasKeyProperties && !hasEnvironmentSigning) {
        throw GradleException(
            "Release signing is not configured. Provide android/key.properties or KICK_ANDROID_KEYSTORE_* environment variables."
        )
    }
}
