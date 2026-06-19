package com.mcweb.connector.velocity;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mcweb.connector.common.BridgeRegistry;
import com.mcweb.connector.common.ConnectorClient;
import com.mcweb.connector.common.PresenceSync;
import com.mcweb.connector.common.LinkCommandConfig;
import com.mcweb.connector.common.ProcessedDeliveryStore;
import com.mcweb.connector.common.ProxyBridgeSupport;
import com.mcweb.connector.common.RemoteBridgeConfig;
import com.mcweb.connector.common.TaskPoller;
import com.velocitypowered.api.event.Subscribe;
import com.velocitypowered.api.event.connection.DisconnectEvent;
import com.velocitypowered.api.event.connection.PostLoginEvent;
import com.velocitypowered.api.event.proxy.ProxyInitializeEvent;
import com.velocitypowered.api.command.CommandManager;
import com.velocitypowered.api.command.SimpleCommand;
import com.velocitypowered.api.plugin.Plugin;
import com.velocitypowered.api.plugin.annotation.DataDirectory;
import com.velocitypowered.api.proxy.Player;
import com.velocitypowered.api.proxy.ProxyServer;
import net.kyori.adventure.text.Component;
import net.kyori.adventure.text.format.NamedTextColor;
import org.slf4j.Logger;

import javax.inject.Inject;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.time.Duration;
import java.util.List;
import java.util.Optional;
import java.util.logging.Level;

@Plugin(id = "mcwebconnector", name = "McWebConnector", version = "1.0.0")
public final class McWebVelocityPlugin {
    private final ProxyServer server;
    private final Logger logger;
    private final Path dataDirectory;
    private final java.util.logging.Logger javaLogger = java.util.logging.Logger.getLogger("mcweb-velocity");
    private ConnectorClient client;
    private ProcessedDeliveryStore deliveryStore;
    private TaskPoller taskPoller;
    private JsonObject remoteConfig;
    private RemoteBridgeConfig remoteBridgeConfig = RemoteBridgeConfig.from(null);
    private LinkCommandConfig linkCommandConfig = LinkCommandConfig.defaults();
    private BridgeRegistry bridges;

    @Inject
    public McWebVelocityPlugin(ProxyServer server, Logger logger, @DataDirectory Path dataDirectory) {
        this.server = server;
        this.logger = logger;
        this.dataDirectory = dataDirectory;
    }

    @Subscribe
    public void onProxyInitialization(ProxyInitializeEvent event) {
        ensureDefaultConfig();
        String websiteUrl = readConfig("website-url", "http://localhost:3000");
        String serverId = readConfig("server-id", "");
        String secret = readConfig("connector-secret", "");

        client = new ConnectorClient(websiteUrl, serverId, secret);
        deliveryStore = new ProcessedDeliveryStore(dataDirectory.toFile());
        taskPoller = new TaskPoller(client, deliveryStore, this::executeTask, javaLogger);
        bridges = ProxyBridgeSupport.create(javaLogger);
        remoteConfig = new JsonObject();
        refreshRemoteConfig();

        server.getScheduler().buildTask(this, this::heartbeat).repeat(Duration.ofSeconds(30)).schedule();
        server.getScheduler().buildTask(this, taskPoller::poll).repeat(Duration.ofSeconds(10)).schedule();
        server.getScheduler().buildTask(this, this::refreshRemoteConfig).repeat(Duration.ofMinutes(5)).schedule();

        CommandManager commands = server.getCommandManager();
        java.util.ArrayList<String> aliases = new java.util.ArrayList<>();
        aliases.add("mcweb");
        aliases.addAll(linkCommandConfig.aliasesFor("website"));
        commands.register(
                commands.metaBuilder("website").aliases(aliases.toArray(new String[0])).build(),
                new WebsiteCommand()
        );
    }

    @Subscribe
    public void onPostLogin(PostLoginEvent event) {
        Player player = event.getPlayer();
        server.getScheduler().buildTask(this, () -> syncPlayer(player, "player.join", false)).schedule();
    }

    @Subscribe
    public void onDisconnect(DisconnectEvent event) {
        Player player = event.getPlayer();
        server.getScheduler().buildTask(this, () -> syncPlayer(player, "player.quit", false)).schedule();
    }

    private void syncPlayer(Player player, String eventName, boolean firstJoin) {
        String serverId = readConfig("server-id", "");
        PresenceSync.sync(
                client,
                javaLogger,
                player.getUniqueId().toString(),
                player.getUsername(),
                "java",
                serverId,
                eventName,
                firstJoin
        );
        PresenceSync.syncPermissionGroups(
                client,
                javaLogger,
                player.getUniqueId().toString(),
                player.getUsername(),
                bridges,
                remoteBridgeConfig,
                "luckperms"
        );
    }

    private void executeTask(JsonObject task, TaskPoller.Completion completion) {
        String taskType = task.get("task_type").getAsString();
        JsonObject payload = task.has("payload") && task.get("payload").isJsonObject()
                ? task.getAsJsonObject("payload")
                : new JsonObject();

        if ("broadcast_announcement".equals(taskType)) {
            String text = payload.has("message") ? payload.get("message").getAsString()
                    : payload.has("title") ? payload.get("title").getAsString() : "";
            server.getAllPlayers().forEach(player -> player.sendMessage(Component.text(text)));
            completion.succeed("announcement broadcast");
            return;
        }

        if ("run_commands".equals(taskType) || "deliver_item".equals(taskType)) {
            if (!payload.has("commands")) {
                completion.fail("missing commands payload");
                return;
            }
            JsonArray commands = payload.getAsJsonArray("commands");
            try {
                for (int i = 0; i < commands.size(); i++) {
                    server.getCommandManager().executeAsync(server.getConsoleCommandSource(), commands.get(i).getAsString());
                }
                completion.succeed("commands executed");
            } catch (Exception ex) {
                completion.fail(ex.getMessage() == null ? "command execution failed" : ex.getMessage());
            }
            return;
        }

        completion.fail("unsupported task type on proxy: " + taskType);
    }

    private void heartbeat() {
        try {
            JsonObject body = new JsonObject();
            body.addProperty("online_players", server.getPlayerCount());
            body.addProperty("max_players", server.getConfiguration().getShowMaxPlayers());
            body.addProperty("version", server.getVersion().getVersion());
            Runtime runtime = Runtime.getRuntime();
            body.addProperty("memory_used_mb", (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024));
            body.addProperty("memory_max_mb", runtime.maxMemory() / (1024 * 1024));
            client.post("heartbeat", body);
        } catch (Exception ex) {
            logger.debug("heartbeat failed", ex);
        }
    }

    private void refreshRemoteConfig() {
        try {
            remoteConfig = client.get("config");
            remoteBridgeConfig = RemoteBridgeConfig.from(remoteConfig);
            linkCommandConfig = LinkCommandConfig.from(remoteConfig);
        } catch (Exception ex) {
            logger.debug("config fetch failed", ex);
        }
    }

    private void linkPlayer(com.velocitypowered.api.command.CommandSource sender, Player player) {
        server.getScheduler().buildTask(this, () -> {
            try {
                JsonObject body = new JsonObject();
                body.addProperty("uuid", player.getUniqueId().toString());
                body.addProperty("username", player.getUsername());
                body.addProperty("platform", "java");
                JsonObject response = client.post("link_codes", body);
                String code = response.get("code").getAsString();
                String url = response.has("link_url")
                        ? response.get("link_url").getAsString()
                        : readConfig("website-url", "http://localhost:3000") + "/app/minecraft/link";
                String template = message("link_code", "Bind code: {code} - visit {url}");
                sender.sendMessage(Component.text(template.replace("{code}", code).replace("{url}", url)));
            } catch (Exception ex) {
                javaLogger.log(Level.WARNING, "link failed", ex);
                sender.sendMessage(Component.text(message("link_failed", "Failed to generate bind code."), NamedTextColor.RED));
            }
        }).schedule();
    }

    private void whoisPlayer(com.velocitypowered.api.command.CommandSource sender, String targetName) {
        server.getScheduler().buildTask(this, () -> {
            try {
                JsonObject body = new JsonObject();
                body.addProperty("username", targetName);
                body.addProperty("platform", "java");
                Optional<Player> online = server.getPlayer(targetName);
                online.ifPresent(player -> body.addProperty("uuid", player.getUniqueId().toString()));
                JsonObject response = client.post("whois", body);
                if (response.has("linked") && response.get("linked").getAsBoolean()) {
                    sender.sendMessage(Component.text("Website: " + response.get("website_username").getAsString(), NamedTextColor.GREEN));
                    if (response.has("trust_level_label")) {
                        sender.sendMessage(Component.text("Trust: " + response.get("trust_level_label").getAsString(), NamedTextColor.GRAY));
                    }
                } else {
                    sender.sendMessage(Component.text(
                            response.has("message") ? response.get("message").getAsString() : "Player not linked.",
                            NamedTextColor.YELLOW));
                }
            } catch (Exception ex) {
                logger.debug("whois failed", ex);
                sender.sendMessage(Component.text("Whois lookup failed.", NamedTextColor.RED));
            }
        }).schedule();
    }

    private String message(String key, String fallback) {
        if (remoteConfig != null && remoteConfig.has("messages") && remoteConfig.getAsJsonObject("messages").has(key)) {
            return remoteConfig.getAsJsonObject("messages").get(key).getAsString();
        }
        return fallback;
    }

    private void ensureDefaultConfig() {
        Path configPath = dataDirectory.resolve("config.toml");
        if (Files.exists(configPath)) {
            return;
        }
        try {
            Files.createDirectories(dataDirectory);
            try (InputStream in = getClass().getResourceAsStream("/config.toml")) {
                if (in != null) {
                    Files.copy(in, configPath);
                } else {
                    Files.writeString(configPath, "website-url = \"http://localhost:3000\"\nserver-id = \"\"\nconnector-secret = \"\"\n");
                }
            }
        } catch (IOException ex) {
            logger.warn("failed to write default config", ex);
        }
    }

    private String readConfig(String key, String fallback) {
        Path configPath = dataDirectory.resolve("config.toml");
        if (!Files.exists(configPath)) {
            return fallback;
        }
        try {
            for (String line : Files.readAllLines(configPath)) {
                String trimmed = line.trim();
                if (trimmed.startsWith(key + " = ")) {
                    return trimmed.substring(key.length() + 3).replace("\"", "").trim();
                }
            }
        } catch (IOException ex) {
            logger.debug("config read failed", ex);
        }
        return fallback;
    }

    private final class WebsiteCommand implements SimpleCommand {
        @Override
        public void execute(Invocation invocation) {
            String[] args = invocation.arguments();
            com.velocitypowered.api.command.CommandSource source = invocation.source();

            if (args.length > 0 && "whois".equalsIgnoreCase(args[0])) {
                if (!(source instanceof Player player)) {
                    source.sendMessage(Component.text("Only players can use whois."));
                    return;
                }
                String target = args.length > 1 ? args[1] : player.getUsername();
                whoisPlayer(source, target);
                return;
            }
            if (args.length > 0 && "reload".equalsIgnoreCase(args[0])) {
                refreshRemoteConfig();
                source.sendMessage(Component.text("McWeb config reloaded."));
                return;
            }
            if (linkCommandConfig.isLinkAction(args.length > 0 ? args[0] : null)) {
                if (source instanceof Player player) {
                    linkPlayer(source, player);
                    return;
                }
            }
            source.sendMessage(Component.text(linkCommandConfig.usageHint()));
        }

        @Override
        public List<String> suggest(Invocation invocation) {
            return List.of(linkCommandConfig.getLinkSubcommand(), "whois", "reload");
        }
    }
}
