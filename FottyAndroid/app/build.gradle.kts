import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.dagger.hilt.android")
    id("com.google.devtools.ksp")
    id("org.jetbrains.kotlin.plugin.serialization")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.inputStream().use { localProperties.load(it) }
}

fun localSecret(name: String): String =
    localProperties.getProperty(name, "")
        .replace("\\", "\\\\")
        .replace("\"", "\\\"")

android {
    namespace = "com.pixelperfect.fotty"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.pixelperfect.fotty"
        minSdk = 26
        targetSdk = 34
        versionCode = 27
        versionName = "1.26"
        manifestPlaceholders["usesCleartextTraffic"] = "true"
        buildConfigField(
            "String",
            "P2P_API_PASSWORD",
            "\"${localSecret("P2P_API_PASSWORD")}\""
        )
        buildConfigField("String", "FOOTBALL_DATA_API_KEY", "\"${localSecret("FOOTBALL_DATA_API_KEY")}\"")
        buildConfigField("String", "RAPID_API_KEY", "\"${localSecret("RAPID_API_KEY")}\"")
        buildConfigField("String", "API_FOOTBALL_KEY", "\"${localSecret("API_FOOTBALL_KEY")}\"")
        buildConfigField(
            "String",
            "FOTTY_WEB_BASE_URL",
            "\"${localSecret("FOTTY_WEB_BASE_URL").ifBlank { "https://fotty.pixel-invoice.com" }}\""
        )
        buildConfigField(
            "boolean",
            "FOTTY_FOOTBALL_PROXY_ENABLED",
            localProperties.getProperty("FOTTY_FOOTBALL_PROXY_ENABLED", "true")
        )

        testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner"
        vectorDrawables {
            useSupportLibrary = true
        }
    }

    buildTypes {
        debug {
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        release {
            manifestPlaceholders["usesCleartextTraffic"] = "false"
            isMinifyEnabled = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
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
        buildConfig = true
    }
    composeOptions {
        kotlinCompilerExtensionVersion = "1.5.8"
    }
    packaging {
        resources {
            excludes += "/META-INF/{AL2.0,LGPL2.1}"
        }
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.12.0")
    implementation("androidx.lifecycle:lifecycle-runtime-ktx:2.7.0")
    implementation("androidx.activity:activity-compose:1.8.2")
    implementation(platform("androidx.compose:compose-bom:2025.01.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.ui:ui-tooling-preview")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material3:material3-window-size-class")
    implementation("androidx.compose.material:material-icons-extended")
    
    // Navigation
    implementation("androidx.navigation:navigation-compose:2.7.6")

    // Hilt
    implementation("com.google.dagger:hilt-android:2.50")
    ksp("com.google.dagger:hilt-android-compiler:2.50")
    implementation("androidx.hilt:hilt-navigation-compose:1.1.0")

    // Retrofit
    implementation("com.squareup.retrofit2:retrofit:2.11.0")
    implementation("com.squareup.retrofit2:converter-kotlinx-serialization:2.11.0")
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.6.2")
    implementation("com.squareup.okhttp3:logging-interceptor:4.12.0")
    implementation("com.squareup.okhttp3:okhttp-dnsoverhttps:4.12.0")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")

    // Coil (Image Loading)
    implementation("io.coil-kt:coil-compose:2.5.0")

    // Media3 (ExoPlayer)
    implementation("androidx.media3:media3-exoplayer:1.2.1")
    implementation("androidx.media3:media3-exoplayer-hls:1.2.1")
    implementation("androidx.media3:media3-exoplayer-dash:1.2.1")
    implementation("androidx.media3:media3-ui:1.2.1")

    // JSoup (HTML Parsing)
    implementation("org.jsoup:jsoup:1.17.2")

    // AndroidX Webkit (Advanced WebView)
    implementation("androidx.webkit:webkit:1.10.0")

    // DataStore
    implementation("androidx.datastore:datastore-preferences:1.0.0")

    // Room
    val roomVersion = "2.6.1"
    implementation("androidx.room:room-runtime:$roomVersion")
    implementation("androidx.room:room-ktx:$roomVersion")
    ksp("androidx.room:room-compiler:$roomVersion")

    // Tooling
    debugImplementation("androidx.compose.ui:ui-tooling")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
