plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "to.nori.android"
    compileSdk = 36

    defaultConfig {
        applicationId = "to.nori.android"
        // 28, weil der Swift-Kern gegen aarch64-unknown-linux-android28
        // gebaut wird. Ein niedrigeres minSdk wäre gelogen: die Bibliothek
        // liefe dort nicht.
        minSdk = 28
        targetSdk = 36
        versionCode = 1
        versionName = "0.1.0"

        ndk {
            abiFilters += "arm64-v8a"
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    // Die Swift-Laufzeit und der Kern liegen als fertige .so vor — gebaut von
    // SwiftPM, eingesammelt von tools/build-android-core.sh. Gradle baut sie
    // nicht, es packt sie nur ein.
    sourceSets["main"].jniLibs.srcDirs("src/main/jniLibs")

    buildTypes {
        debug {
            isMinifyEnabled = false
        }
        release {
            isMinifyEnabled = false
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        compose = true
    }

    packaging {
        jniLibs {
            // Die Swift-Laufzeit bringt eigene .so mit, die nicht
            // komprimiert werden dürfen, damit der Linker sie direkt aus dem
            // APK laden kann.
            useLegacyPackaging = false
        }
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.8.7")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    debugImplementation("androidx.compose.ui:ui-tooling")
}
