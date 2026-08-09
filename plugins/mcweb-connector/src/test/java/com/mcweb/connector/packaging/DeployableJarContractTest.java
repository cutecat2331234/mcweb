package com.mcweb.connector.packaging;

import org.junit.jupiter.api.Test;

import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.URLClassLoader;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.Enumeration;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.util.jar.JarEntry;
import java.util.jar.JarFile;
import java.util.stream.Collectors;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

final class DeployableJarContractTest {
    private static final String CONNECTOR_CLIENT = "com/mcweb/connector/common/ConnectorClient.class";
    private static final String OKHTTP_CLIENT = "com/mcweb/connector/internal/okhttp3/OkHttpClient.class";
    private static final String GSON = "com/mcweb/connector/internal/gson/Gson.class";

    private static final List<String> FORBIDDEN_PLATFORM_PREFIXES = Arrays.asList(
            "org/bukkit/",
            "net/md_5/bungee/",
            "com/velocitypowered/api/"
    );

    private static final List<ArtifactContract> CONTRACTS = Arrays.asList(
            new ArtifactContract(
                    "mcweb-connector-bukkit-legacy",
                    "com/mcweb/connector/bukkit/legacy/McWebConnectorLegacyPlugin.class",
                    "plugin.yml",
                    "main: com.mcweb.connector.bukkit.legacy.McWebConnectorLegacyPlugin",
                    52
            ),
            new ArtifactContract(
                    "mcweb-connector-bukkit-modern",
                    "com/mcweb/connector/bukkit/modern/McWebConnectorPlugin.class",
                    "plugin.yml",
                    "main: com.mcweb.connector.bukkit.modern.McWebConnectorPlugin",
                    65
            ),
            new ArtifactContract(
                    "mcweb-connector-bungee",
                    "com/mcweb/connector/bungee/McWebBungeePlugin.class",
                    "bungee.yml",
                    "main: com.mcweb.connector.bungee.McWebBungeePlugin",
                    52
            ),
            new ArtifactContract(
                    "mcweb-connector-velocity",
                    "com/mcweb/connector/velocity/McWebVelocityPlugin.class",
                    null,
                    "Lcom/velocitypowered/api/plugin/Plugin;",
                    61
            )
    );

    @Test
    void deploymentDirectoryContainsExactlyTheFourSelfContainedPlatformJars() throws Exception {
        Path projectDir = requiredPathProperty("connector.projectDir");
        Path deployableDir = requiredPathProperty("connector.deployableDir");
        String version = requiredProperty("connector.version");

        Set<String> expectedJarNames = CONTRACTS.stream()
                .map(contract -> contract.module + "-" + version + ".jar")
                .collect(Collectors.toSet());
        Set<String> actualJarNames;
        try (java.util.stream.Stream<Path> files = Files.list(deployableDir)) {
            actualJarNames = files
                    .filter(path -> path.getFileName().toString().endsWith(".jar"))
                    .map(path -> path.getFileName().toString())
                    .collect(Collectors.toSet());
        }
        assertEquals(expectedJarNames, actualJarNames, "deployment directory must contain only the four platform jars");

        for (ArtifactContract contract : CONTRACTS) {
            Path deployableJar = deployableDir.resolve(contract.module + "-" + version + ".jar");
            Path thinJar = projectDir.resolve(contract.module)
                    .resolve("build/libs")
                    .resolve(contract.module + "-" + version + "-plain.jar");

            assertTrue(Files.isRegularFile(deployableJar), "missing deployable jar: " + deployableJar);
            assertTrue(Files.isRegularFile(thinJar), "missing thin jar: " + thinJar);
            verifyDeployableJar(deployableJar, contract);
            verifyThinJar(thinJar, contract);
        }
    }

    @Test
    void readmePointsOperatorsToDeployableJarsAndRejectsThinJars() throws Exception {
        Path readmePath = requiredPathProperty("connector.projectDir").resolve("README.md");
        String readme = new String(Files.readAllBytes(readmePath), StandardCharsets.UTF_8);

        assertTrue(readme.contains("build/deployable/"), "README must identify the deployment directory");
        assertTrue(readme.contains("-plain.jar"), "README must identify thin jars by classifier");
        assertTrue(readme.contains("不能作为服务器部署文件"), "README must reject thin jars as deployment artifacts");
        assertFalse(
                readme.contains("产物位于各子模块 `build/libs/`"),
                "README must not describe module build/libs directories as the deployment output"
        );
    }

    private static void verifyDeployableJar(Path path, ArtifactContract contract) throws Exception {
        try (JarFile jar = new JarFile(path.toFile())) {
            List<String> entries = entryNames(jar);
            assertContains(entries, contract.mainClass, path);
            assertContains(entries, CONNECTOR_CLIENT, path);
            assertContains(entries, OKHTTP_CLIENT, path);
            assertContains(entries, GSON, path);
            if (contract.metadata != null) {
                assertContains(entries, contract.metadata, path);
                assertEntryContains(jar, contract.metadata, contract.metadataMarker, path);
            } else {
                assertEntryContains(jar, contract.mainClass, contract.metadataMarker, path);
            }

            for (String prefix : FORBIDDEN_PLATFORM_PREFIXES) {
                assertFalse(
                        entries.stream().anyMatch(name -> name.startsWith(prefix)),
                        () -> path + " must not bundle server-owned API classes under " + prefix
                );
            }
            assertFalse(
                    entries.stream().anyMatch(DeployableJarContractTest::isSignatureEntry),
                    () -> path + " contains an invalid dependency signature"
            );
            assertEquals(
                    Collections.emptySet(),
                    duplicateEntries(entries),
                    path + " contains duplicate jar entries"
            );
            assertEquals(
                    contract.expectedClassMajor,
                    classMajorVersion(jar, contract.mainClass),
                    path + " has the wrong Java target for its platform entrypoint"
            );
            assertAllClassesCompatible(jar, contract.expectedClassMajor, path);
        }
        verifyConnectorClientCanInitialize(path);
    }

    private static void verifyThinJar(Path path, ArtifactContract contract) throws Exception {
        try (JarFile jar = new JarFile(path.toFile())) {
            List<String> entries = entryNames(jar);
            assertContains(entries, contract.mainClass, path);
            if (contract.metadata != null) {
                assertContains(entries, contract.metadata, path);
            }
            assertFalse(entries.contains(CONNECTOR_CLIENT), path + " must remain a thin jar");
            assertFalse(entries.contains(OKHTTP_CLIENT), path + " must remain a thin jar");
            assertFalse(entries.contains(GSON), path + " must remain a thin jar");
        }
    }

    private static List<String> entryNames(JarFile jar) {
        List<String> names = new ArrayList<>();
        Enumeration<JarEntry> entries = jar.entries();
        while (entries.hasMoreElements()) {
            names.add(entries.nextElement().getName());
        }
        return names;
    }

    private static Set<String> duplicateEntries(List<String> entries) {
        Map<String, Integer> counts = new HashMap<>();
        for (String entry : entries) {
            counts.put(entry, counts.getOrDefault(entry, 0) + 1);
        }
        Set<String> duplicates = new HashSet<>();
        for (Map.Entry<String, Integer> count : counts.entrySet()) {
            if (count.getValue() > 1) {
                duplicates.add(count.getKey());
            }
        }
        return duplicates;
    }

    private static boolean isSignatureEntry(String name) {
        String upper = name.toUpperCase(Locale.ROOT);
        if (!upper.startsWith("META-INF/")) {
            return false;
        }
        return upper.endsWith(".SF")
                || upper.endsWith(".DSA")
                || upper.endsWith(".RSA")
                || upper.endsWith(".EC");
    }

    private static int classMajorVersion(JarFile jar, String classEntry) throws IOException {
        JarEntry entry = jar.getJarEntry(classEntry);
        assertNotNull(entry, "missing class entry: " + classEntry);
        return classMajorVersion(jar, entry);
    }

    private static void assertEntryContains(JarFile jar, String entryName, String marker, Path path) throws IOException {
        JarEntry entry = jar.getJarEntry(entryName);
        assertNotNull(entry, path + " is missing metadata entry " + entryName);
        byte[] bytes;
        try (InputStream input = jar.getInputStream(entry)) {
            bytes = input.readAllBytes();
        }
        String contents = new String(bytes, StandardCharsets.ISO_8859_1);
        assertTrue(
                contents.contains(marker),
                () -> path + " metadata " + entryName + " is missing marker " + marker
        );
    }

    private static int classMajorVersion(JarFile jar, JarEntry entry) throws IOException {
        byte[] header = new byte[8];
        try (InputStream input = jar.getInputStream(entry)) {
            int offset = 0;
            while (offset < header.length) {
                int read = input.read(header, offset, header.length - offset);
                if (read < 0) {
                    break;
                }
                offset += read;
            }
            assertEquals(header.length, offset, "truncated class entry: " + entry.getName());
        }
        assertEquals(0xCA, header[0] & 0xFF, "invalid class magic: " + entry.getName());
        assertEquals(0xFE, header[1] & 0xFF, "invalid class magic: " + entry.getName());
        assertEquals(0xBA, header[2] & 0xFF, "invalid class magic: " + entry.getName());
        assertEquals(0xBE, header[3] & 0xFF, "invalid class magic: " + entry.getName());
        return ((header[6] & 0xFF) << 8) | (header[7] & 0xFF);
    }

    private static void assertAllClassesCompatible(JarFile jar, int maximumMajor, Path path) throws IOException {
        Enumeration<JarEntry> entries = jar.entries();
        while (entries.hasMoreElements()) {
            JarEntry entry = entries.nextElement();
            String name = entry.getName();
            if (entry.isDirectory()
                    || !name.endsWith(".class")
                    || name.startsWith("META-INF/versions/")) {
                continue;
            }
            int major = classMajorVersion(jar, entry);
            assertTrue(
                    major <= maximumMajor,
                    () -> path + " contains " + name + " with class major " + major
                            + ", above platform maximum " + maximumMajor
            );
        }
    }

    private static void verifyConnectorClientCanInitialize(Path path) throws Exception {
        URL[] classpath = new URL[]{path.toUri().toURL()};
        try (URLClassLoader loader = new URLClassLoader(classpath, ClassLoader.getPlatformClassLoader())) {
            Class<?> connectorClient = Class.forName(
                    "com.mcweb.connector.common.ConnectorClient",
                    true,
                    loader
            );
            Object instance = connectorClient
                    .getConstructor(String.class, String.class, String.class)
                    .newInstance("http://127.0.0.1", "contract-test", "contract-test-secret");
            assertNotNull(instance, path + " must initialize ConnectorClient with its private dependencies");
        }
    }

    private static void assertContains(List<String> entries, String expected, Path path) {
        assertTrue(entries.contains(expected), () -> path + " is missing " + expected);
    }

    private static Path requiredPathProperty(String key) {
        return Paths.get(requiredProperty(key));
    }

    private static String requiredProperty(String key) {
        String value = System.getProperty(key);
        assertNotNull(value, "missing system property " + key);
        assertFalse(value.isEmpty(), "empty system property " + key);
        return value;
    }

    private static final class ArtifactContract {
        private final String module;
        private final String mainClass;
        private final String metadata;
        private final String metadataMarker;
        private final int expectedClassMajor;

        private ArtifactContract(
                String module,
                String mainClass,
                String metadata,
                String metadataMarker,
                int expectedClassMajor
        ) {
            this.module = module;
            this.mainClass = mainClass;
            this.metadata = metadata;
            this.metadataMarker = metadataMarker;
            this.expectedClassMajor = expectedClassMajor;
        }
    }
}
