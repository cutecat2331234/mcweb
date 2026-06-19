plugins {
    java
}

dependencies {
    implementation(project(":mcweb-connector-common"))
    compileOnly("org.spigotmc:spigot-api:1.8.8-R0.1-SNAPSHOT")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(8))
    }
}
