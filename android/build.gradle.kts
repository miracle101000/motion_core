group = "com.example.motion_core"
version = "0.2.0"

buildscript {
    // Kept on the classpath so Flutter's Gradle plugin can apply the Kotlin
    // Gradle Plugin to this project on apps that no longer declare it
    // themselves (see the built-in Kotlin migration guide). This plugin does
    // not apply KGP itself.
    val kotlinVersion = "2.3.20"
    repositories {
        google()
        mavenCentral()
    }

    dependencies {
        classpath("com.android.tools.build:gradle:9.0.1")
        classpath("org.jetbrains.kotlin:kotlin-gradle-plugin:$kotlinVersion")
    }
}

allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

plugins {
    id("com.android.library")
}

android {
    namespace = "com.example.motion_core"

    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            java.srcDirs("src/main/kotlin")
        }
        getByName("test") {
            java.srcDirs("src/test/kotlin")
        }
    }

    defaultConfig {
        minSdk = 21
    }

    testOptions {
        unitTests {
            isIncludeAndroidResources = true
            all {
                it.useJUnitPlatform()

                it.outputs.upToDateWhen { false }

                it.testLogging {
                    events("passed", "skipped", "failed", "standardOut", "standardError")
                    showStandardStreams = true
                }
            }
        }
    }
}

// Built-in Kotlin: no kotlin-android plugin and no android.kotlinOptions.
kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    // Pinned explicitly: without KGP applied by this script there is no
    // automatic kotlin-test variant/version selection.
    testImplementation(platform("org.junit:junit-bom:5.12.2"))
    testImplementation("org.jetbrains.kotlin:kotlin-test-junit5:2.3.20")
    testImplementation("org.mockito:mockito-core:5.0.0")
    // Gradle 9 no longer puts the JUnit Platform launcher on the classpath for you.
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}
