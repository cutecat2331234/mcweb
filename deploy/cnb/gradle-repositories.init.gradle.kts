import org.gradle.api.artifacts.repositories.MavenArtifactRepository

private const val aliyunPublic = "https://maven.aliyun.com/repository/public/"
private const val aliyunGradlePlugin = "https://maven.aliyun.com/repository/gradle-plugin/"

fun org.gradle.api.artifacts.dsl.RepositoryHandler.prependMirror(
    repositoryName: String,
    repositoryUrl: String
) {
    if (withType(MavenArtifactRepository::class.java).none { it.url.toString() == repositoryUrl }) {
        maven {
            name = repositoryName
            url = uri(repositoryUrl)
        }
    }
}

settingsEvaluated {
    pluginManagement.repositories.apply {
        prependMirror("AliyunGradlePlugin", aliyunGradlePlugin)
        prependMirror("AliyunPublic", aliyunPublic)
        gradlePluginPortal()
    }
}

allprojects {
    repositories.apply {
        prependMirror("AliyunPublic", aliyunPublic)
    }
}
