import com.github.jengelman.gradle.plugins.shadow.tasks.ShadowJar
import org.gradle.api.file.DuplicatesStrategy
import org.gradle.api.tasks.Sync
import org.gradle.api.tasks.bundling.Jar
import org.gradle.api.tasks.testing.Test

plugins {
    java
    id("com.gradleup.shadow") version "9.2.2" apply false
}

val deployableConnectorProjects = listOf(
    "mcweb-connector-bukkit-legacy",
    "mcweb-connector-bukkit-modern",
    "mcweb-connector-bungee",
    "mcweb-connector-velocity"
)

allprojects {
    group = "com.mcweb"
    version = "1.0.0"
}

repositories {
    mavenCentral()
}

subprojects {
    apply(plugin = "java")

    if (name in deployableConnectorProjects) {
        apply(plugin = "com.gradleup.shadow")

        tasks.named<Jar>("jar") {
            archiveClassifier.set("plain")
        }

        tasks.named<ShadowJar>("shadowJar") {
            archiveClassifier.set("")

            // Service descriptors need to be merged before duplicate resources
            // are discarded. Signed dependency metadata must never survive
            // repackaging because the resulting signature would be invalid.
            duplicatesStrategy = DuplicatesStrategy.INCLUDE
            mergeServiceFiles()
            filesNotMatching("META-INF/services/**") {
                duplicatesStrategy = DuplicatesStrategy.EXCLUDE
            }
            exclude(
                "META-INF/INDEX.LIST",
                "META-INF/*.SF",
                "META-INF/*.DSA",
                "META-INF/*.RSA",
                "META-INF/*.EC"
            )

            // Minecraft platforms and other plugins may ship different library
            // versions. Keep Connector's private runtime isolated and do not use
            // minimize(), because bridge integrations are discovered by reflection.
            relocate("com.google.gson", "com.mcweb.connector.internal.gson")
            relocate("okhttp3", "com.mcweb.connector.internal.okhttp3")
            relocate("okio", "com.mcweb.connector.internal.okio")
            relocate("kotlin", "com.mcweb.connector.internal.kotlin")
            relocate("kotlinx", "com.mcweb.connector.internal.kotlinx")

            isPreserveFileTimestamps = false
            isReproducibleFileOrder = true
        }
    }

    repositories {
        mavenCentral()
        maven("https://repo.papermc.io/repository/maven-public/")
        maven("https://hub.spigotmc.org/nexus/content/repositories/snapshots/")
        maven("https://oss.sonatype.org/content/repositories/snapshots/")
    }

    dependencies {
        // Pinned to 5.12.x: junit-jupiter 5.13+ requires Java 17 at runtime, but
        // these connector modules use a Java 8 toolchain (bukkit-legacy targets
        // old servers). Declare the platform-launcher explicitly and pin it to the
        // matching 1.12.2 so it stays aligned with the 5.12.2 engine — Gradle's
        // auto-injected launcher is a different version and breaks JUnit test
        // discovery with "OutputDirectoryProvider not available".
        testImplementation("org.junit.jupiter:junit-jupiter:5.12.2")
        testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.12.2")
    }

    tasks.test {
        useJUnitPlatform()
    }

    tasks.withType<JavaCompile>().configureEach {
        options.encoding = "UTF-8"
    }
}

dependencies {
    testImplementation("org.junit.jupiter:junit-jupiter:5.12.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher:1.12.2")
}

val platformShadowJars = deployableConnectorProjects.map { projectName ->
    project(":$projectName").tasks.named<ShadowJar>("shadowJar")
}
val platformThinJars = deployableConnectorProjects.map { projectName ->
    project(":$projectName").tasks.named<Jar>("jar")
}

val stageDeployableJars by tasks.registering(Sync::class) {
    group = "distribution"
    description = "Stages the four self-contained Connector plugin jars."
    dependsOn(platformShadowJars)
    into(layout.buildDirectory.dir("deployable"))
    platformShadowJars.forEach { shadowJar ->
        from(shadowJar.flatMap { it.archiveFile })
    }
}

tasks.named("assemble") {
    dependsOn(stageDeployableJars)
}

tasks.named<Test>("test") {
    dependsOn(stageDeployableJars, platformThinJars)
    useJUnitPlatform()
    systemProperty("connector.projectDir", projectDir.absolutePath)
    systemProperty("connector.deployableDir", layout.buildDirectory.dir("deployable").get().asFile.absolutePath)
    systemProperty("connector.version", version.toString())
}

tasks.withType<JavaCompile>().configureEach {
    options.encoding = "UTF-8"
}
