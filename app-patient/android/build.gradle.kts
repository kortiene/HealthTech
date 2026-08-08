allprojects {
    repositories {
        google()
        mavenCentral()
    }
    // audio_session (just_audio dep) pins AGP 8.1.0 in its own build.gradle.
    // Force the version that is already in the local Gradle cache so the build
    // works without network access (the real version is set by settings.gradle.kts).
    configurations.all {
        resolutionStrategy.eachDependency {
            if (requested.group == "com.android.tools.build" && requested.name == "gradle") {
                useVersion("8.7.3")
                because("audio_session pins 8.1.0; override to the cached version")
            }
        }
    }
}

val newBuildDir: Directory = rootProject.layout.buildDirectory.dir("../../build").get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
