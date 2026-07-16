allprojects {
    repositories {
        google()
        mavenCentral()
        // ReVanced's patcher/library artifacts are only published to GitHub
        // Packages, which requires authentication even for public read access.
        // Set githubPackagesUsername/githubPackagesPassword (a GitHub PAT with
        // read:packages) in ~/.gradle/gradle.properties or as
        // ORG_GRADLE_PROJECT_githubPackages{Username,Password} env vars to build
        // the "normal" flavor. The "fdroid" flavor does not need this.
        maven {
            name = "reVancedGitHubPackages"
            // "registry" is a dummy path - GitHub Packages Maven resolution is
            // scoped to the org, not this specific repo name (mirrors the same
            // dummy URL revanced-manager's own settings.gradle.kts uses).
            url = uri("https://maven.pkg.github.com/revanced/registry")
            credentials {
                username = providers.gradleProperty("githubPackagesUsername").orNull
                password = providers.gradleProperty("githubPackagesPassword").orNull
            }
        }
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
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
