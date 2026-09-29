import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Build identification (shown in Settings → Info): git commit, whether the
// working tree had uncommitted changes, and the commit count as versionCode,
// so every APK handed out can be traced back to an exact source state.
fun git(vararg args: String): String = try {
    providers.exec { commandLine("git", *args); isIgnoreExitValue = true }
        .standardOutput.asText.get().trim()
} catch (e: Exception) { "" }

val gitSha = git("rev-parse", "--short=7", "HEAD").ifEmpty { "unknown" }
val gitDirty = git("status", "--porcelain", "--untracked-files=no").isNotEmpty()
val gitCommitCount = git("rev-list", "--count", "HEAD").toIntOrNull()
val buildTime = ZonedDateTime.now()
    .format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm"))

val uploadKey = rootProject.file("key.properties").takeIf { it.exists() }
    ?.let { f -> Properties().apply { f.inputStream().use { load(it) } } }

android {
    namespace = "at.oe1cko.nextcwtrainer"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    externalNativeBuild {
        cmake {
            path = file("CMakeLists.txt")
            version = "3.22.1"
        }
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "at.oe1cko.nextcwtrainer"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26  // AAudio requires API 26
        targetSdk = flutter.targetSdkVersion

        externalNativeBuild {
            cmake {
                cppFlags += "-std=c++17"
                abiFilters += listOf("arm64-v8a", "x86_64")
            }
        }
        // Package only the ABIs libcw_audio is built for. Flutter would add
        // armeabi-v7a, where System.loadLibrary("cw_audio") crashes; this also
        // keeps Play from offering the app to 32-bit-only devices.
        ndk {
            abiFilters += listOf("arm64-v8a", "x86_64")
        }
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        // Build number = git commit count (monotonic, unique per commit);
        // falls back to the pubspec build number outside a git checkout.
        versionCode = gitCommitCount ?: flutter.versionCode
        versionName = flutter.versionName

        buildConfigField("String", "GIT_SHA", "\"$gitSha\"")
        buildConfigField("boolean", "GIT_DIRTY", "$gitDirty")
        buildConfigField("String", "BUILD_TIME", "\"$buildTime\"")
    }

    buildFeatures {
        buildConfig = true
    }

    // Play upload key: android/key.properties (gitignored, never committed)
    // with storeFile/storePassword/keyAlias/keyPassword. Without it, release
    // builds fall back to the debug key so `flutter run --release` still works;
    // tools/build_release.sh refuses to build without it.
    signingConfigs {
        uploadKey?.let { key ->
            create("upload") {
                storeFile = file(key.getProperty("storeFile"))
                storePassword = key.getProperty("storePassword")
                keyAlias = key.getProperty("keyAlias")
                keyPassword = key.getProperty("keyPassword")
            }
        }
    }

    // Debug builds use the upload key too (when present) so a plain
    // `flutter build apk --debug` installs over the test phone's current
    // app without re-signing by hand. Other machines fall back to the
    // default debug key.
    buildTypes {
        debug {
            if (uploadKey != null) signingConfig = signingConfigs.getByName("upload")
        }
        release {
            signingConfig = signingConfigs.getByName(
                if (uploadKey != null) "upload" else "debug")
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
