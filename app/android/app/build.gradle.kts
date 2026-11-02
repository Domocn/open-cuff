import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "io.github.domocn.open_cuff"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true // flutter_local_notifications
    }

    defaultConfig {
        applicationId = "io.github.domocn.open_cuff"
        minSdk = 26 // Health Connect
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // Release signing: the maintainer's key lives outside the project (android/key.properties, or
    // ~/.keys/open-cuff/key.properties). Anyone else building gets the debug key, which is fine for their own phone.
    val keyProps = Properties().apply {
        listOf(rootProject.file("key.properties"), file("${System.getProperty("user.home")}/.keys/open-cuff/key.properties"))
            .firstOrNull { it.exists() }?.inputStream()?.use { load(it) }
    }
    signingConfigs {
        if (keyProps.getProperty("storeFile") != null) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
