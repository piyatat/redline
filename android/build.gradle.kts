plugins {
    alias(libs.plugins.android.application) apply false
    alias(libs.plugins.android.library) apply false
    alias(libs.plugins.kotlin.android) apply false
    alias(libs.plugins.kotlin.compose) apply false
}

// Root owns the Gradle Wrapper. IDEs sometimes invoke :AndroidDemo:wrapper — delegate.
tasks.named<Wrapper>("wrapper") {
    gradleVersion = "8.11.1"
    distributionType = Wrapper.DistributionType.BIN
}

// IntelliJ / Android Studio sync invokes these on each module; register no-ops when missing.
fun Project.registerIdeSyncStubs() {
    if (tasks.findByName("prepareKotlinBuildScriptModel") == null) {
        tasks.register("prepareKotlinBuildScriptModel") {
            group = "ide"
            description = "Stub for Android Studio / IntelliJ Kotlin DSL model import"
        }
    }
    if (tasks.findByName("wrapper") == null) {
        tasks.register("wrapper") {
            group = "build setup"
            description = "Delegates to the root project Gradle Wrapper task"
            dependsOn(rootProject.tasks.named("wrapper"))
        }
    }
}

registerIdeSyncStubs()

subprojects {
    afterEvaluate {
        registerIdeSyncStubs()
    }
    // Also register early so sync can find the task before afterEvaluate.
    registerIdeSyncStubs()
}
