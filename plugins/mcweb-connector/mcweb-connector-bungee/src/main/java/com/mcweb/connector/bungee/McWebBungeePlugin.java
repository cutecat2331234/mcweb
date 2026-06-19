package com.mcweb.connector.bungee;

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
        taskPoller = new TaskPoller(client, deliveryStore, this::executeTask, getLogger());
        bridges = ProxyBridgeSupport.create(getLogger());
        remoteConfig = new JsonObject();
        refreshRemoteConfig();

        getProxy().getPluginManager().registerListener(this, this);
        getProxy().getScheduler().schedule(this, this::heartbeat, 5, 30, TimeUnit.SECONDS);
        getProxy().getScheduler().schedule(this, taskPoller::poll, 10, 10, TimeUnit.SECONDS);
        getProxy().getScheduler().schedule(this, this::refreshRemoteConfig, 1, 5, TimeUnit.MINUTES);

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
        getProxy().getScheduler().runAsync(this, new Runnable() {
            @Override
            public void run() {
                syncPlayer(player, "player.join", false);
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
        PresenceSync.sync(
                client,
                getLogger(),
                player.getUniqueId().toString(),
                player.getName(),
                "java",
                serverId,
                eventName,
                firstJoin
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
            JsonArray commands = payload.getAsJsonArray("commands");
            try {
                for (int i = 0; i < commands.size(); i++) {
                    getProxy().getPluginManager().dispatchCommand(getProxy().getConsole(), commands.get(i).getAsString());
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
            body.addProperty("online_players", getProxy().getOnlineCount());
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
                    JsonObject body = new JsonObject();
                    body.addProperty("uuid", player.getUniqueId().toString());
                    body.addProperty("username", player.getName());
                    body.addProperty("platform", "java");
                    JsonObject response = client.post("link_codes", body);
                    String code = response.get("code").getAsString();
                    String url = response.has("link_url")
                            ? response.get("link_url").getAsString()
                            : config.getString("website-url", "http://localhost:3000") + "/app/minecraft/link";
                    String template = message("link_code", "Bind code: {code} - visit {url}");
                    sender.sendMessage(ChatColor.GREEN + template.replace("{code}", code).replace("{url}", url));
                } catch (Exception ex) {
                    getLogger().log(Level.WARNING, "link failed", ex);
                    sender.sendMessage(ChatColor.RED + message("link_failed", "Failed to generate bind code."));
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
                    if (response.has("linked") && response.get("linked").getAsBoolean()) {
                        sender.sendMessage(ChatColor.GREEN + "Website: " + response.get("website_username").getAsString());
                        if (response.has("trust_level_label")) {
                            sender.sendMessage(ChatColor.GRAY + "Trust: " + response.get("trust_level_label").getAsString());
                        }
                    } else {
                        sender.sendMessage(ChatColor.YELLOW + (response.has("message") ? response.get("message").getAsString() : "Player not linked."));
                    }
                } catch (Exception ex) {
                    getLogger().log(Level.FINE, "whois failed", ex);
                    sender.sendMessage(ChatColor.RED + "Whois lookup failed.");
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
                refreshRemoteConfig();
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
