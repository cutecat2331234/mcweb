plugins {
    java
}

dependencies {
    implementation(project(":mcweb-connector-common"))
    compileOnly("com.velocitypowered:velocity-api:3.3.0-SNAPSHOT")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(17))
    }
}

tasks.withType<JavaCompile>().configureEach {
    options.release.set(17)
}
