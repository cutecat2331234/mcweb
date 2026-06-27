plugins {
    java
}

dependencies {
    implementation("com.squareup.okhttp3:okhttp:3.14.9")
    implementation("com.google.code.gson:gson:2.10.1")
}

java {
    toolchain {
        languageVersion.set(JavaLanguageVersion.of(8))
    }
}

// junit-jupiter's platform/engine needs a newer JVM than this module's Java 8
// runtime target. Keep main bytecode at Java 8 (bukkit-legacy depends on this
// module for old servers), but compile and run the dev-only tests on Java 17.
tasks.named<JavaCompile>("compileTestJava") {
    javaCompiler.set(javaToolchains.compilerFor {
        languageVersion.set(JavaLanguageVersion.of(17))
    })
}
tasks.named<Test>("test") {
    javaLauncher.set(javaToolchains.launcherFor {
        languageVersion.set(JavaLanguageVersion.of(17))
    })
}
