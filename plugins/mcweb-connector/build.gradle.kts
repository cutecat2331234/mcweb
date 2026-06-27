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
        // Pinned to 5.12.x: junit-jupiter 5.13+ requires Java 17 at runtime,
        // but these connector modules use a Java 8 toolchain (bukkit-legacy
        // targets old servers), so the Java 8 test JVM can't load a 5.13 engine.
        testImplementation("org.junit.jupiter:junit-jupiter:5.12.2")
    }

    tasks.test {
        useJUnitPlatform()
        testLogging {
            events("passed", "skipped", "failed")
            exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
            showStandardStreams = true
        }
    }

    tasks.withType<JavaCompile>().configureEach {
        options.encoding = "UTF-8"
    }
}
