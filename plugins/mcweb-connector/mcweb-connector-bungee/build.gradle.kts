plugins {
    java
}

dependencies {
    implementation(project(":mcweb-connector-common"))
    compileOnly("net.md-5:bungeecord-api:1.20-R0.2")
    implementation("net.md-5:bungeecord-config:1.20-R0.2")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(8))
    }
}
