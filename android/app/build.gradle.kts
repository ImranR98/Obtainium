import java.io.FileInputStream
import java.util.Properties
import com.android.build.api.variant.FilterConfiguration.FilterType.*
import com.android.build.gradle.internal.api.ApkVariantOutputImpl

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val localProperties = Properties()
val localPropertiesFile = rootProject.file("local.properties")
if (localPropertiesFile.exists()) {
    localPropertiesFile.reader(Charsets.UTF_8).use { reader ->
        localProperties.load(reader)
    }
}

var flutterVersionCode = localProperties.getProperty("flutter.versionCode") ?: "1"
var flutterVersionName = localProperties.getProperty("flutter.versionName") ?: "1.0"

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val keystorePropertiesExists = keystorePropertiesFile.exists()
if (keystorePropertiesExists) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.imranr.obtainium"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "28.2.13676358"

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "dev.imranr.obtainium"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutterVersionCode.toInt()
        versionName = flutterVersionName
    }

    flavorDimensions += "default"

    productFlavors {
        create("normal") {
            dimension = "default"
            applicationIdSuffix = ""
        }
        create("fdroid") {
            dimension = "default"
            applicationIdSuffix = ".fdroid"
        }
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }

    buildTypes {
        getByName("release") {
            val releaseSigningConfig = signingConfigs.getByName("release")
            signingConfig = if (keystorePropertiesExists && releaseSigningConfig.storeFile != null) {
                releaseSigningConfig
            } else {
                if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
                    logger.error(
                        """
                            WARNING: You are trying to create a release build, but a key.properties file was not found.
                                     You will need to sign the APKs separately.

                            To sign a release build automatically, a keystore properties file is required.

                            The following is an example configuration.
                            Create a file named [project]/android/key.properties that contains a reference to your keystore.
                            Don't include the angle brackets (< >). They indicate that the text serves as a placeholder for your values.

                            storePassword=<keystore password>
                            keyPassword=<key password>
                            keyAlias=<key alias>
                            storeFile=<keystore file location>

                            For more info, see:
                            * https://docs.flutter.dev/deployment/android#sign-the-app
                        """.trimIndent()
                    )
                }
                null
            }
        }
        getByName("debug") {
            applicationIdSuffix = ".debug"
            versionNameSuffix = "-debug"
        }
    }
}

val abiCodes = mapOf("x86_64" to 1, "armeabi-v7a" to 2, "arm64-v8a" to 3)

android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode = abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride = variant.versionCode * 10 + abiVersionCode
        }
    }
}


// revanced-library pulls in a proto dependency that conflicts with one already on
// the classpath; revanced-manager works around it the same way.
configurations.all {
    exclude(group = "com.google.api.grpc", module = "proto-google-common-protos")
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")

    // ReVanced patching support. Deliberately scoped to the "normal" flavor only -
    // F-Droid's inclusion policy prohibits apps that download and execute compiled
    // code fetched at runtime (exactly what loading a patch bundle jar does), so
    // the fdroid flavor never links these and RevancedIntegration is a no-op there.
    "normalImplementation"("app.revanced:patcher-android:22.0.2-dev.1")
    "normalImplementation"("app.revanced:library-android:4.0.0")
    "normalImplementation"("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.9.0")
}

flutter {
    source = "../.."
}
