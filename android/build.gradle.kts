allprojects {
    repositories {
        google()
        mavenCentral()
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
subprojects {
    if (name == "cronet_http") {
        // Always embed Cronet so no build (including F-Droid) depends on Play Services.
        val defines = (findProperty("dart-defines") as String?)
            ?.split(',')
            ?.filter { it.isNotBlank() }
            .orEmpty()
        val embedded = java.util.Base64.getEncoder()
            .encodeToString("cronetHttpNoPlay=true".toByteArray())
        extensions.extraProperties["dart-defines"] =
            (defines + embedded).joinToString(",")
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
