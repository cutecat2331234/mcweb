package com.mcweb.connector.bungee;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mcweb.connector.common.BridgeRegistry;
import com.mcweb.connector.common.ConnectorClient;
import com.mcweb.connector.common.PresenceSync;
import com.mcweb.connector.common.LinkCodes;
import com.mcweb.connector.common.LinkCommandConfig;
import com.mcweb.connector.common.LinkResponseHelper;
import com.mcweb.connector.common.OnlinePlayerRoster;
import com.mcweb.connector.common.ProcessedDeliveryStore;
import com.mcweb.connector.common.ProxyBridgeSupport;
import com.mcweb.connector.common.RemoteBridgeConfig;
import com.mcweb.connector.common.TaskPoller;
import com.mcweb.connector.common.WhoisDisplayHelper;
import net.md_5.bungee.api.ChatColor;
import net.md_5.bungee.api.CommandSender;
import net.md_5.bungee.api.connection.ProxiedPlayer;
import net.md_5.bungee.api.event.PlayerDisconnectEvent;
import net.md_5.bungee.api.event.PostLoginEvent;
import net.md_5.bungee.api.plugin.Command;
import net.md_5.bungee.api.plugin.Listener;
import net.md_5.bungee.api.plugin.Plugin;
import net.md_5.bungee.config.Configuration;
import net.md_5.bungee.config.ConfigurationProvider;
import net.md_5.bungee.config.YamlConfiguration;
import net.md_5.bungee.event.EventHandler;

import java.io.File;
import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.util.ArrayList;
import java.util.concurrent.TimeUnit;
import java.util.logging.Level;

public final class McWebBungeePlugin extends Plugin implements Listener {
    private ConnectorClient client;
    private ProcessedDeliveryStore deliveryStore;
    private ProcessedDeliveryStore seenPlayerStore;
    private TaskPoller taskPoller;
    private JsonObject remoteConfig;
    private RemoteBridgeConfig remoteBridgeConfig = RemoteBridgeConfig.from(null);
    private LinkCommandConfig linkCommandConfig = LinkCommandConfig.defaults();
    private BridgeRegistry bridges;
    private Configuration config;
    private WebsiteCommand websiteCommand;

    @Override
    public void onEnable() {
        loadConfig();
        client = new ConnectorClient(
                config.getString("website-url", "http://localhost:3000"),
                config.getString("server-id", ""),
                config.getString("connector-secret", "")
        );
        deliveryStore = new ProcessedDeliveryStore(getDataFolder());
        seenPlayerStore = new ProcessedDeliveryStore(getDataFolder(), "seen_players.txt");
        taskPoller = new TaskPoller(client, deliveryStore, this::executeTask, getLogger());
        bridges = ProxyBridgeSupport.create(getLogger());
        remoteConfig = new JsonObject();
        refreshRemoteConfig();

        getProxy().getPluginManager().registerListener(this, this);
        getProxy().getScheduler().schedule(this, () -> getProxy().getScheduler().runAsync(this, this::heartbeat), 5, 30, TimeUnit.SECONDS);
        getProxy().getScheduler().schedule(this, () -> getProxy().getScheduler().runAsync(this, () -> taskPoller.poll()), 10, 10, TimeUnit.SECONDS);
        getProxy().getScheduler().schedule(this, () -> getProxy().getScheduler().runAsync(this, this::refreshRemoteConfig), 1, 5, TimeUnit.MINUTES);

        registerWebsiteCommand();
    }

    private void loadConfig() {
        if (!getDataFolder().exists()) {
            getDataFolder().mkdir();
        }
        File file = new File(getDataFolder(), "config.yml");
        if (!file.exists()) {
            try (InputStream in = getResourceAsStream("config.yml")) {
                if (in != null) {
                    Files.copy(in, file.toPath());
                }
            } catch (IOException ex) {
                getLogger().log(Level.WARNING, "failed to write default config", ex);
            }
        }
        try {
            config = ConfigurationProvider.getProvider(YamlConfiguration.class).load(file);
        } catch (IOException ex) {
            getLogger().log(Level.SEVERE, "failed to load config", ex);
            config = new Configuration();
        }
    }

    private void reloadConnectorClient() {
        client = new ConnectorClient(
                config.getString("website-url", "http://localhost:3000"),
                config.getString("server-id", ""),
                config.getString("connector-secret", "")
        );
        taskPoller = new TaskPoller(client, deliveryStore, this::executeTask, getLogger());
    }

    private void registerWebsiteCommand() {
        ArrayList<String> aliases = new ArrayList<String>();
        aliases.add("mcweb");
        aliases.addAll(linkCommandConfig.aliasesFor("website"));
        if (websiteCommand != null) {
            getProxy().getPluginManager().unregisterCommand(websiteCommand);
        }
        websiteCommand = new WebsiteCommand(aliases.toArray(new String[0]));
        getProxy().getPluginManager().registerCommand(this, websiteCommand);
    }

    @EventHandler
    public void onPostLogin(PostLoginEvent event) {
        ProxiedPlayer player = event.getPlayer();
        final boolean firstJoin = seenPlayerStore.registerIfNew(player.getUniqueId().toString());
        getProxy().getScheduler().runAsync(this, new Runnable() {
            @Override
            public void run() {
                syncPlayer(player, "player.join", firstJoin);
            }
        });
    }

    @EventHandler
    public void onDisconnect(PlayerDisconnectEvent event) {
        ProxiedPlayer player = event.getPlayer();
        getProxy().getScheduler().runAsync(this, new Runnable() {
            @Override
            public void run() {
                syncPlayer(player, "player.quit", false);
            }
        });
    }

    private void syncPlayer(ProxiedPlayer player, String eventName, boolean firstJoin) {
        String serverId = config.getString("server-id", "");
        java.util.ArrayList<java.util.UUID> onlineIds = new java.util.ArrayList<java.util.UUID>();
        for (ProxiedPlayer online : getProxy().getPlayers()) {
            onlineIds.add(online.getUniqueId());
        }
        PresenceSync.sync(
                client,
                getLogger(),
                player.getUniqueId().toString(),
                player.getName(),
                "java",
                serverId,
                eventName,
                firstJoin,
                OnlinePlayerRoster.fromUuids(onlineIds)
        );
        PresenceSync.syncPermissionGroups(
                client,
                getLogger(),
                player.getUniqueId().toString(),
                player.getName(),
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
            getProxy().broadcast(ChatColor.translateAlternateColorCodes('&', text));
            completion.succeed("announcement broadcast");
            return;
        }

        if ("run_commands".equals(taskType) || "deliver_item".equals(taskType)) {
            if (!payload.has("commands")) {
                completion.fail("missing commands payload");
                return;
            }
            final JsonArray commands = payload.getAsJsonArray("commands");
            getProxy().getScheduler().schedule(this, new Runnable() {
                @Override
                public void run() {
                    try {
                        for (int i = 0; i < commands.size(); i++) {
                            getProxy().getPluginManager().dispatchCommand(
                                    getProxy().getConsole(),
                                    commands.get(i).getAsString()
                            );
                        }
                        completion.succeed("commands executed");
                    } catch (Exception ex) {
                        completion.fail(ex.getMessage() == null ? "command execution failed" : ex.getMessage());
                    }
                }
            }, 0, TimeUnit.MILLISECONDS);
            return;
        }

        completion.fail("unsupported task type on proxy: " + taskType);
    }

    private void heartbeat() {
        try {
            java.util.ArrayList<java.util.UUID> onlineIds = new java.util.ArrayList<java.util.UUID>();
            for (ProxiedPlayer online : getProxy().getPlayers()) {
                onlineIds.add(online.getUniqueId());
            }
            JsonObject body = new JsonObject();
            body.addProperty("online_players", getProxy().getOnlineCount());
            body.add("online_player_uuids", OnlinePlayerRoster.fromUuids(onlineIds));
            body.addProperty("max_players", getProxy().getConfig().getPlayerLimit());
            body.addProperty("version", getProxy().getVersion());
            Runtime runtime = Runtime.getRuntime();
            body.addProperty("memory_used_mb", (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024));
            body.addProperty("memory_max_mb", runtime.maxMemory() / (1024 * 1024));
            client.post("heartbeat", body);
        } catch (Exception ex) {
            getLogger().log(Level.FINE, "heartbeat failed", ex);
        }
    }

    private void refreshRemoteConfig() {
        try {
            remoteConfig = client.get("config");
            remoteBridgeConfig = RemoteBridgeConfig.from(remoteConfig);
            linkCommandConfig = LinkCommandConfig.from(remoteConfig);
            registerWebsiteCommand();
        } catch (Exception ex) {
            getLogger().log(Level.FINE, "config fetch failed", ex);
        }
    }

    private String message(String key, String fallback) {
        if (remoteConfig != null && remoteConfig.has("messages") && remoteConfig.getAsJsonObject("messages").has(key)) {
            return remoteConfig.getAsJsonObject("messages").get(key).getAsString();
        }
        return fallback;
    }

    private void linkPlayer(CommandSender sender, ProxiedPlayer player) {
        getProxy().getScheduler().runAsync(this, new Runnable() {
            @Override
            public void run() {
                try {
                    String code = LinkCodes.generateCode(8);
                    JsonObject body = new JsonObject();
                    body.addProperty("uuid", player.getUniqueId().toString());
                    body.addProperty("username", player.getName());
                    body.addProperty("platform", "java");
                    body.addProperty("code_digest", LinkCodes.digestCode(code));
                    JsonObject response = client.post("link_codes", body);
                    String outboundCode = LinkResponseHelper.resolveCode(response, code);
                    String url = response.has("link_url")
                            ? response.get("link_url").getAsString()
                            : config.getString("website-url", "http://localhost:3000") + "/app/minecraft/link";
                    final String template = message("link_code", "Bind code: {code} - visit {url}");
                    final String outbound = ChatColor.GREEN + template.replace("{code}", outboundCode).replace("{url}", url);
                    getProxy().getScheduler().schedule(McWebBungeePlugin.this, new Runnable() {
                        @Override
                        public void run() {
                            sender.sendMessage(outbound);
                        }
                    }, 0, TimeUnit.MILLISECONDS);
                } catch (Exception ex) {
                    getLogger().log(Level.WARNING, "link failed", ex);
                    final String failed = ChatColor.RED + message("link_failed", "Failed to generate bind code.");
                    getProxy().getScheduler().schedule(McWebBungeePlugin.this, new Runnable() {
                        @Override
                        public void run() {
                            sender.sendMessage(failed);
                        }
                    }, 0, TimeUnit.MILLISECONDS);
                }
            }
        });
    }

    private void whoisPlayer(CommandSender sender, String targetName) {
        getProxy().getScheduler().runAsync(this, new Runnable() {
            @Override
            public void run() {
                try {
                    JsonObject body = new JsonObject();
                    body.addProperty("username", targetName);
                    body.addProperty("platform", "java");
                    ProxiedPlayer online = getProxy().getPlayer(targetName);
                    if (online != null) {
                        body.addProperty("uuid", online.getUniqueId().toString());
                    }
                JsonObject response = client.post("whois", body);
                final java.util.List<String> lines = WhoisDisplayHelper.displayLines(response);
                getProxy().getScheduler().schedule(McWebBungeePlugin.this, new Runnable() {
                        @Override
                        public void run() {
                            for (String line : lines) {
                                sender.sendMessage(line);
                            }
                        }
                    }, 0, TimeUnit.MILLISECONDS);
                } catch (Exception ex) {
                    getLogger().log(Level.FINE, "whois failed", ex);
                    getProxy().getScheduler().schedule(McWebBungeePlugin.this, new Runnable() {
                        @Override
                        public void run() {
                            sender.sendMessage(ChatColor.RED + WhoisDisplayHelper.lookupFailedMessage(remoteConfig));
                        }
                    }, 0, TimeUnit.MILLISECONDS);
                }
            }
        });
    }

    private final class WebsiteCommand extends Command {
        WebsiteCommand(String[] aliases) {
            super("website", null, aliases);
        }

        @Override
        public void execute(CommandSender sender, String[] args) {
            if (args.length > 0 && "whois".equalsIgnoreCase(args[0])) {
                if (!(sender instanceof ProxiedPlayer)) {
                    sender.sendMessage("Only players can use whois.");
                    return;
                }
                String target = args.length > 1 ? args[1] : ((ProxiedPlayer) sender).getName();
                whoisPlayer(sender, target);
                return;
            }
            if (args.length > 0 && "reload".equalsIgnoreCase(args[0])) {
                loadConfig();
                reloadConnectorClient();
                refreshRemoteConfig();
                registerWebsiteCommand();
                sender.sendMessage("McWeb config reloaded.");
                return;
            }
            if (linkCommandConfig.isLinkAction(args.length > 0 ? args[0] : null)) {
                if (sender instanceof ProxiedPlayer) {
                    linkPlayer(sender, (ProxiedPlayer) sender);
                    return;
                }
            }
            sender.sendMessage(linkCommandConfig.usageHint());
        }
    }
}
