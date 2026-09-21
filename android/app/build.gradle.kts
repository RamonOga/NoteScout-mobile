// Импорт обязателен: без него `java.util.Properties` не резолвится, потому что
// `java` в Kotlin DSL перехватывается свойством Project.java.
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Подпись релизных сборок.
//
// Параметры ключа читаются из android/key.properties, который в репозиторий не
// попадает (см. README, раздел «Сборка»). Если файла нет — на свежем клоне, в
// CI без секретов или в локальной сборке «на посмотреть» — релиз подписывается
// отладочным ключом, чтобы `flutter build apk --release` работал без настройки.
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
val keystoreProperties = Properties()

if (hasReleaseKeystore) {
    keystorePropertiesFile.inputStream().use { keystoreProperties.load(it) }
    val required = listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
    val missing = required.filter { keystoreProperties.getProperty(it).isNullOrBlank() }
    if (missing.isNotEmpty()) {
        throw GradleException(
            "android/key.properties есть, но в нём не хватает полей: " +
                missing.joinToString(", ") +
                ". Нужны все четыре: storeFile, storePassword, keyAlias, keyPassword."
        )
    }
} else {
    logger.warn(
        "android/key.properties не найден: релизная сборка будет подписана " +
            "отладочным ключом. Такой APK ставится на телефон, но обновить им " +
            "уже установленное приложение нельзя, если оно ставилось сборкой " +
            "с другого ключа. Как завести свой ключ — README, раздел «Сборка»."
    )
}

android {
    namespace = "com.notescout.mobile"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.notescout.mobile"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
                // storeFile задаётся в key.properties относительно android/app.
                storeFile = file(keystoreProperties.getProperty("storeFile") as String)
                storePassword = keystoreProperties.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // Отладочный ключ: сборка годится для установки и проверки,
                // но не для обновления уже установленного приложения.
                signingConfigs.getByName("debug")
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
