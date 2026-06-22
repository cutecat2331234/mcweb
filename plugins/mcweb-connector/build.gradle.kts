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
        testImplementation("org.junit.jupiter:junit-jupiter:5.13.4")
    }

    tasks.test {
        useJUnitPlatform()
    }

    tasks.withType<JavaCompile>().configureEach {
        options.encoding = "UTF-8"
    }
}
