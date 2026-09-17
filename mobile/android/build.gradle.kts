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

// F-Droid compares its rebuild of every release APK byte for byte against the
// one signed by the maintainer, and `libdartjni.so` (built out of the jni
// plugin's CMake project) is where that falls apart: AGP gives every CMake
// configure under the pub cache an unpredictable name such as
// /tmp/pubcache/.../.cxx/RelWithDebInfo/<random8>, which survives into the
// debug info. Gradle strips the debug info before packaging, but the ELF
// .note.gnu.build-id was hashed from the pre-strip bytes, so the stripped
// file still carries the randomness in its build-id while every other byte
// matches. Nothing in AGP lets us name the folder, so instead this hook
// deletes the note uniformly on both pipelines: with only the note gone, a
// build on the F-Droid server and the GHA release build end up byte
// identical (`llvm-objcopy` output is fully deterministic)
subprojects {
    afterEvaluate {
        val objcopy = extensions.findByName("android")
            ?.let { it as com.android.build.gradle.BaseExtension }
            ?.ndkDirectory
            ?.walk()
            ?.firstOrNull { it.isFile && it.name == "llvm-objcopy" }
            ?: return@afterEvaluate
        tasks.matching { it.name.startsWith("strip") && it.name.contains("Release") }.configureEach {
            doLast {
                project.layout.buildDirectory.get().asFile
                    .resolve("intermediates/stripped_native_libs")
                    .walkTopDown()
                    .forEach { dir ->
                        if (dir.isDirectory) {
                            dir.resolve("libdartjni.so").takeIf(File::isFile)?.let { lib ->
                                project.exec {
                                    commandLine(
                                        objcopy.absolutePath,
                                        "--remove-section=.note.gnu.build-id",
                                        lib.absolutePath
                                    )
                                }
                            }
                        }
                    }
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
