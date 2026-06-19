package com.mcweb.connector.bukkit.modern;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mcweb.connector.common.BridgeRegistry;
import com.mcweb.connector.common.ConnectorClient;
import com.mcweb.connector.common.ConnectorEvents;
import com.mcweb.connector.common.PresenceSync;
import com.mcweb.connector.common.LinkCommandConfig;
import com.mcweb.connector.common.ProcessedDeliveryStore;
import com.mcweb.connector.common.RemoteBridgeConfig;
import com.mcweb.connector.common.TaskPoller;
import org.bukkit.Bukkit;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.plugin.java.JavaPlugin;
import org.bukkit.scheduler.BukkitRunnable;

import java.util.logging.Level;

public final class McWebConnectorPlugin extends JavaPlugin implements Listener {
    private ConnectorClient client;
    private BridgeSupport.Holder bridges;
    private ProcessedDeliveryStore deliveryStore;
    private TaskPoller taskPoller;
    private JsonObject remoteConfig;
    private RemoteBridgeConfig remoteBridgeConfig = RemoteBridgeConfig.from(null);
    private LinkCommandConfig linkCommandConfig = LinkCommandConfig.defaults();

    @Override
    public void onEnable() {
        saveDefaultConfig();
        client = new ConnectorClient(
                getConfig().getString("website-url", "http://localhost:3000"),
                getConfig().getString("server-id", ""),
                getConfig().getString("connector-secret", "")
        );
        bridges = BridgeSupport.create(this);
        deliveryStore = new ProcessedDeliveryStore(getDataFolder());
        taskPoller = new TaskPoller(client, deliveryStore, this::executeTask, getLogger());
        remoteConfig = new JsonObject();
        getServer().getPluginManager().registerEvents(this, this);
        refreshRemoteConfig();
        new BukkitRunnable() {
            @Override
            public void run() {
                sendHeartbeat();
            }
        }.runTaskTimerAsynchronously(this, 20L, 20L * 30);
        new BukkitRunnable() {
            @Override
            public void run() {
                taskPoller.poll();
            }
        }.runTaskTimerAsynchronously(this, 40L, 20L * 10);
        new BukkitRunnable() {
            @Override
            public void run() {
                refreshRemoteConfig();
            }
        }.runTaskTimerAsynchronously(this, 20L * 5, 20L * 60 * 5);
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player)) {
            sender.sendMessage("Only players can use this command.");
            return true;
        }
        Player player = (Player) sender;
        if (linkCommandConfig.isLinkAction(args.length > 0 ? args[0] : null)) {
            linkPlayer(player);
            return true;
        }
        if ("whois".equalsIgnoreCase(args[0])) {
            String target = args.length > 1 ? args[1] : player.getName();
            whoisPlayer(player, target);
            return true;
        }
        if ("reload".equalsIgnoreCase(args[0])) {
            reloadConfig();
            refreshRemoteConfig();
            sender.sendMessage("McWeb config reloaded.");
            return true;
        }
        sender.sendMessage(linkCommandConfig.usageHint());
        return true;
    }

    private void linkPlayer(Player player) {
        Bukkit.getScheduler().runTaskAsynchronously(this, () -> {
            try {
                JsonObject body = new JsonObject();
                body.addProperty("uuid", player.getUniqueId().toString());
                body.addProperty("username", player.getName());
                body.addProperty("platform", "java");
                JsonObject response = client.post("link_codes", body);
                String code = response.get("code").getAsString();
                String url = response.has("link_url") ? response.get("link_url").getAsString() : getConfig().getString("website-url") + "/app/minecraft/link";
                String template = message("link_code", "Bind code: {code} - visit {url}");
                player.sendMessage(template.replace("{code}", code).replace("{url}", url));
            } catch (Exception ex) {
                getLogger().log(Level.WARNING, "link failed", ex);
                player.sendMessage(message("link_failed", "Failed to generate bind code. Try again later."));
            }
        });
    }

    private void whoisPlayer(Player requester, String targetName) {
        Bukkit.getScheduler().runTaskAsynchronously(this, () -> {
            try {
                JsonObject body = new JsonObject();
                body.addProperty("username", targetName);
                body.addProperty("platform", "java");
                Player online = Bukkit.getPlayerExact(targetName);
                if (online != null) {
                    body.addProperty("uuid", online.getUniqueId().toString());
                }
                JsonObject response = client.post("whois", body);
                if (response.has("linked") && response.get("linked").getAsBoolean()) {
                    requester.sendMessage("Website: " + response.get("website_username").getAsString());
                    if (response.has("trust_level_label")) {
                        requester.sendMessage("Trust: " + response.get("trust_level_label").getAsString());
                    }
                } else {
                    requester.sendMessage(response.has("message") ? response.get("message").getAsString() : "Player not linked.");
                }
            } catch (Exception ex) {
                getLogger().log(Level.FINE, "whois failed", ex);
                requester.sendMessage("Whois lookup failed.");
            }
        });
    }

    private void executeTask(JsonObject task, TaskPoller.Completion completion) {
        String taskType = task.get("task_type").getAsString();
        JsonObject payload = task.has("payload") && task.get("payload").isJsonObject()
                ? task.getAsJsonObject("payload")
                : new JsonObject();

        if ("broadcast_announcement".equals(taskType)) {
            String text = payload.has("message") ? payload.get("message").getAsString() : payload.has("title") ? payload.get("title").getAsString() : "";
            Bukkit.getScheduler().runTask(this, () -> Bukkit.broadcastMessage(text));
            completion.succeed("announcement broadcast");
            return;
        }

        if ("run_commands".equals(taskType) || "deliver_item".equals(taskType)) {
            if (!payload.has("commands")) {
                completion.fail("missing commands payload");
                return;
            }
            JsonArray commands = payload.getAsJsonArray("commands");
            Bukkit.getScheduler().runTask(this, () -> {
                try {
                    for (int j = 0; j < commands.size(); j++) {
                        Bukkit.dispatchCommand(Bukkit.getConsoleSender(), commands.get(j).getAsString());
                    }
                    completion.succeed("commands executed");
                } catch (Exception ex) {
                    completion.fail(ex.getMessage() == null ? "command execution failed" : ex.getMessage());
                }
            });
            return;
        }

        completion.fail("unsupported task type: " + taskType);
    }

    @EventHandler
    public void onJoin(PlayerJoinEvent event) {
        syncPresence(event.getPlayer(), "player.join", !event.getPlayer().hasPlayedBefore());
    }

    @EventHandler
    public void onQuit(PlayerQuitEvent event) {
        syncPresence(event.getPlayer(), "player.quit", false);
    }

    private void syncPresence(Player player, String eventName, boolean firstJoin) {
        Bukkit.getScheduler().runTaskAsynchronously(this, () -> {
            try {
                String serverId = getConfig().getString("server-id", "");

                JsonObject presenceBody = new JsonObject();
                presenceBody.addProperty("uuid", player.getUniqueId().toString());
                presenceBody.addProperty("username", player.getName());
                presenceBody.addProperty("platform", "java");
                presenceBody.addProperty("event", eventName);
                appendSkinProperties(player, presenceBody);
                client.post("presence", presenceBody);

                PresenceSync.syncProfileFields(
                        client,
                        getLogger(),
                        player.getUniqueId().toString(),
                        player.getName(),
                        bridges.registry,
                        remoteBridgeConfig
                );
                PresenceSync.syncPermissionGroups(
                        client,
                        getLogger(),
                        player.getUniqueId().toString(),
                        player.getName(),
                        bridges.registry,
                        remoteBridgeConfig,
                        "luckperms"
                );

                JsonObject eventPayload = new JsonObject();
                eventPayload.addProperty("uuid", player.getUniqueId().toString());
                eventPayload.addProperty("username", player.getName());
                eventPayload.addProperty("platform", "java");
                eventPayload.addProperty("server_id", serverId);
                ConnectorEvents.post(
                        client,
                        getLogger(),
                        eventName,
                        eventName + "-" + player.getUniqueId() + "-" + System.currentTimeMillis(),
                        eventPayload
                );
                if (firstJoin) {
                    ConnectorEvents.post(
                            client,
                            getLogger(),
                            "player.first_join",
                            "first-join-" + player.getUniqueId(),
                            eventPayload
                    );
                }
            } catch (Exception ex) {
                getLogger().log(Level.FINE, "presence sync failed", ex);
            }
        });
    }

    private void appendSkinProperties(Player player, JsonObject body) {
        try {
            Object profile = player.getClass().getMethod("getPlayerProfile").invoke(player);
            if (profile == null) {
                return;
            }
            Object textures = profile.getClass().getMethod("getTextures").invoke(profile);
            if (textures == null) {
                return;
            }
            Object skin = textures.getClass().getMethod("getSkin").invoke(textures);
            if (skin != null) {
                String skinUrl;
                if (skin instanceof java.net.URL) {
                    skinUrl = ((java.net.URL) skin).toExternalForm();
                } else {
                    skinUrl = String.valueOf(skin);
                }
                body.addProperty("skin_texture", skinUrl);
            }
            Object model = textures.getClass().getMethod("getSkinModel").invoke(textures);
            if (model != null) {
                body.addProperty("skin_model", model.toString().toLowerCase());
            }
        } catch (Exception ignored) {
        }
    }

    private void sendHeartbeat() {
        try {
            JsonObject body = new JsonObject();
            body.addProperty("online_players", Bukkit.getOnlinePlayers().size());
            body.addProperty("max_players", Bukkit.getMaxPlayers());
            body.addProperty("version", Bukkit.getVersion());
            body.addProperty("motd", Bukkit.getMotd());
            JsonArray plugins = new JsonArray();
            for (org.bukkit.plugin.Plugin plugin : Bukkit.getPluginManager().getPlugins()) {
                JsonObject entry = new JsonObject();
                entry.addProperty("name", plugin.getName());
                entry.addProperty("version", plugin.getDescription().getVersion());
                plugins.add(entry);
            }
            body.add("plugins", plugins);
            Runtime runtime = Runtime.getRuntime();
            body.addProperty("memory_used_mb", (runtime.totalMemory() - runtime.freeMemory()) / (1024 * 1024));
            body.addProperty("memory_max_mb", runtime.maxMemory() / (1024 * 1024));
            double tps = readTps();
            if (tps > 0) {
                body.addProperty("tps", tps);
            }
            client.post("heartbeat", body);
        } catch (Exception ex) {
            getLogger().log(Level.FINE, "heartbeat failed", ex);
        }
    }

    private double readTps() {
        try {
            Object server = Bukkit.getServer().getClass().getMethod("getServer").invoke(Bukkit.getServer());
            double[] recentTps = (double[]) server.getClass().getField("recentTps").get(server);
            return recentTps.length > 0 ? recentTps[0] : 0D;
        } catch (Exception ignored) {
            return 0D;
        }
    }

    private void refreshRemoteConfig() {
        try {
            remoteConfig = client.get("config");
            remoteBridgeConfig = RemoteBridgeConfig.from(remoteConfig);
            linkCommandConfig = LinkCommandConfig.from(remoteConfig);
            bridges.applyRemoteConfig(remoteBridgeConfig);
            applyLinkCommandAliases();
        } catch (Exception ex) {
            getLogger().log(Level.FINE, "config fetch failed", ex);
        }
    }

    private void applyLinkCommandAliases() {
        org.bukkit.command.PluginCommand command = getCommand("website");
        if (command == null) {
            return;
        }
        java.util.List<String> aliases = linkCommandConfig.aliasesFor("website");
        if (!aliases.isEmpty()) {
            command.setAliases(aliases);
        }
    }

    private String message(String key, String fallback) {
        if (remoteConfig != null && remoteConfig.has("messages") && remoteConfig.getAsJsonObject("messages").has(key)) {
            return remoteConfig.getAsJsonObject("messages").get(key).getAsString();
        }
        return fallback;
    }
}
