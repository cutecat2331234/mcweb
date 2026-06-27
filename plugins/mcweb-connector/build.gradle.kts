plugins {
    java
}

allprojects {
    group = "com.mcweb"
    version = "1.0.0"
}

subprojects {
    apply(plugin = "java")

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
