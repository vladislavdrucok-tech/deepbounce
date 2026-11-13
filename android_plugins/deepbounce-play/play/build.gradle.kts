plugins {
    id("com.android.library")
    id("org.jetbrains.kotlin.android")
}

val pluginName = "DeepBouncePlay"
val pluginPackageName = "com.deepbounce.play"

// Keep these two in sync with addons/DeepBouncePlay/export_plugin.gd (_get_android_dependencies)
val gamesVersion = "21.0.0"
val reviewVersion = "2.0.2"

android {
    namespace = pluginPackageName
    compileSdk = 35

    buildFeatures { buildConfig = true }

    defaultConfig {
        minSdk = 24
        manifestPlaceholders["godotPluginName"] = pluginName
        manifestPlaceholders["godotPluginPackageName"] = pluginPackageName
        buildConfigField("String", "GODOT_PLUGIN_NAME", "\"${pluginName}\"")
        setProperty("archivesBaseName", pluginName)
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
}

dependencies {
    compileOnly("org.godotengine:godot:4.5.1.stable")
    implementation("com.google.android.gms:play-services-games-v2:$gamesVersion")
    implementation("com.google.android.play:review:$reviewVersion")
}

val copyAars by tasks.registering(Copy::class) {
    from("build/outputs/aar")
    include("$pluginName-release.aar", "$pluginName-debug.aar")
    into(rootProject.file("../../addons/$pluginName/bin"))
}
tasks.named("assemble").configure { finalizedBy(copyAars) }
