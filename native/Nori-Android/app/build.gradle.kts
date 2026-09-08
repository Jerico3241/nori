plugins {
    // Kein `kotlin.android` mehr: seit AGP 9 bringt das Android-Plugin die
    // Kotlin-Unterstützung selbst mit, und es zusätzlich anzuwenden ist ein
    // Fehler. Die Compiler-Plugins für Compose und Serialisierung bleiben —
    // das sind eigene Erweiterungen, keine zweite Kotlin-Anbindung.
    alias(libs.plugins.android.application)
    alias(libs.plugins.kotlin.compose)
    alias(libs.plugins.kotlin.serialization)
}

android {
    namespace = "de.nori"
    // 37, nicht 36: Compose 1.12 und okhttp-android 5.5 verlangen es
    // ausdrücklich („requires libraries and applications that depend on it to
    // compile against version 37 or later"). Der Build bricht sonst schon in
    // der Abhängigkeitsprüfung ab. `minSdk` bleibt davon unberührt — die
    // App läuft weiter ab Android 9.
    compileSdk = 37

    defaultConfig {
        applicationId = "de.nori"
        minSdk = 28
        targetSdk = 37
        versionCode = 1
        versionName = "1.0.0"

        // Nur die beiden ABIs, für die NoriCore gebaut wird. Ein drittes
        // stillschweigend mitzupacken hieße: eine APK, die auf dem Gerät am
        // fehlenden libNoriAndroid.so stirbt.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
    }

    // Die .so-Dateien kommen fertig aus dem SwiftPM-Build (siehe
    // tools/collect-android-libs.py). Kein NDK, kein CMake im Gradle-Build.
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")

    packaging {
        resources {
            excludes += setOf("/META-INF/{AL2.0,LGPL2.1}", "META-INF/DEPENDENCIES")
        }
    }

    buildTypes {
        debug {
            applicationIdSuffix = ".debug"
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
            // Ohne Signatur ist die APK nicht installierbar. Ein
            // Debug-Schlüssel ist für ein privates Projekt der richtige
            // Kompromiss: die Datei lässt sich aufs Gerät ziehen, ohne dass
            // ein echter Schlüssel in die CI muss.
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    buildFeatures {
        compose = true
        buildConfig = true
    }
}

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17)
        // Media3 kennzeichnet weite Teile seiner API als @UnstableApi. Das
        // ist bei einer Bibliothek dieser Reichweite normal und kein Grund,
        // jede Datei mit @OptIn zu pflastern — hier steht die Entscheidung
        // einmal.
        freeCompilerArgs.addAll(
            "-opt-in=androidx.media3.common.util.UnstableApi",
            // ModalBottomSheet und rememberModalBottomSheetState sind
            // weiterhin als experimentell gekennzeichnet. Ohne Opt-in ist
            // das ein Uebersetzungsfehler, kein Hinweis.
            "-opt-in=androidx.compose.material3.ExperimentalMaterial3Api",
        )
    }
}

dependencies {
    implementation(libs.androidx.core.ktx)
    implementation(libs.androidx.activity.compose)
    implementation(libs.androidx.lifecycle.runtime.ktx)
    implementation(libs.androidx.lifecycle.runtime.compose)
    implementation(libs.androidx.lifecycle.viewmodel.compose)
    implementation(libs.androidx.lifecycle.process)

    implementation(platform(libs.androidx.compose.bom))
    implementation(libs.androidx.compose.ui)
    implementation(libs.androidx.compose.ui.graphics)
    implementation(libs.androidx.compose.ui.tooling.preview)
    implementation(libs.androidx.compose.material3)
    implementation(libs.androidx.compose.material.icons)
    debugImplementation(libs.androidx.compose.ui.tooling)

    implementation(libs.androidx.navigation.compose)
    implementation(libs.androidx.datastore.preferences)

    implementation(libs.androidx.media3.common)
    implementation(libs.androidx.media3.exoplayer)
    implementation(libs.androidx.media3.exoplayer.hls)
    implementation(libs.androidx.media3.exoplayer.dash)
    implementation(libs.androidx.media3.datasource.okhttp)
    implementation(libs.androidx.media3.session)

    implementation(libs.kotlinx.coroutines.android)
    implementation(libs.kotlinx.serialization.json)

    implementation(libs.coil.compose)
    implementation(libs.coil.network.okhttp)
    implementation(libs.okhttp)
}
