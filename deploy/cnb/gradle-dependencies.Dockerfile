FROM eclipse-temurin:8-jdk@sha256:3525194d19338fd143e2038bd5e848e335f50d04e89ba8734c0458df8d494254 AS jdk8

FROM eclipse-temurin:17-jdk@sha256:a27c79d44326d5f689668df5fedfee487652066d2a91e172747056cc7fbee6fc AS jdk17

FROM gradle:8.14.5-jdk21@sha256:66e8f1cd9019bb5dbc9084ebdc1717251db6479ac810ae80fe8fcf236c8d6ce9

USER root

COPY --from=jdk8 --chown=gradle:gradle /opt/java/openjdk /opt/mcweb-jdks/jdk8
COPY --from=jdk17 --chown=gradle:gradle /opt/java/openjdk /opt/mcweb-jdks/jdk17

ENV MCWEB_JDK8_HOME=/opt/mcweb-jdks/jdk8 \
    MCWEB_JDK17_HOME=/opt/mcweb-jdks/jdk17

RUN /opt/mcweb-jdks/jdk8/bin/java -version && \
    /opt/mcweb-jdks/jdk8/bin/javac -version && \
    /opt/mcweb-jdks/jdk17/bin/java -version && \
    /opt/mcweb-jdks/jdk17/bin/javac -version && \
    mkdir -p /home/gradle/.gradle && \
    printf '%s\n' \
      'org.gradle.java.installations.fromEnv=MCWEB_JDK8_HOME,MCWEB_JDK17_HOME,JAVA_HOME' \
      > /home/gradle/.gradle/gradle.properties && \
    chown -R gradle:gradle /home/gradle/.gradle

USER gradle
WORKDIR /opt/mcweb-dependency-cache

COPY --chown=gradle:gradle plugins/mcweb-connector ./plugins/mcweb-connector

RUN cd plugins/mcweb-connector && \
    chmod +x gradlew && \
    ./gradlew --console=plain --info --no-daemon build && \
    rm -rf /opt/mcweb-dependency-cache/plugins

WORKDIR /workspace
