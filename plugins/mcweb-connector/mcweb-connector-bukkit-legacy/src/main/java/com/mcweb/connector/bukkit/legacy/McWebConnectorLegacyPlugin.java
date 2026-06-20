package com.mcweb.connector.bukkit.legacy;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.mcweb.connector.common.ConnectorClient;
import com.mcweb.connector.common.ConnectorEvents;
import com.mcweb.connector.common.PresenceSync;
import com.mcweb.connector.common.LinkCodes;
import com.mcweb.connector.common.LinkCommandConfig;
import com.mcweb.connector.common.LinkResponseHelper;
import com.mcweb.connector.common.OnlinePlayerRoster;
import com.mcweb.connector.common.ProcessedDeliveryStore;
import com.mcweb.connector.common.RemoteBridgeConfig;
import com.mcweb.connector.common.TaskPoller;
import com.mcweb.connector.common.WhoisDisplayHelper;
import org.bukkit.Bukkit;
import org.bukkit.command.Command;
import org.bukkit.command.CommandSender;
import org.bukkit.entity.Player;
import org.bukkit.event.EventHandler;
import org.bukkit.event.Listener;
import org.bukkit.event.player.PlayerJoinEvent;
import org.bukkit.event.player.PlayerQuitEvent;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.logging.Level;

public final class McWebConnectorLegacyPlugin extends JavaPlugin implements Listener {
    private ConnectorClient client;
    private LegacyBridgeSupport.Holder bridges;
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
        bridges = LegacyBridgeSupport.create(this);
        deliveryStore = new ProcessedDeliveryStore(getDataFolder());
        taskPoller = new TaskPoller(client, deliveryStore, this::executeTask, getLogger());
        remoteConfig = new JsonObject();
        getServer().getPluginManager().registerEvents(this, this);
        refreshRemoteConfigAsync();
        Bukkit.getScheduler().runTaskTimer(this, new Runnable() {
            @Override
            public void run() {
                sendHeartbeat();
            }
        }, 20L * 5, 20L * 30);
        Bukkit.getScheduler().runTaskTimerAsynchronously(this, new Runnable() {
            @Override
            public void run() {
                taskPoller.poll();
            }
        }, 40L, 20L * 10);
        Bukkit.getScheduler().runTaskTimerAsynchronously(this, new Runnable() {
            @Override
            public void run() {
                refreshRemoteConfigAsync();
            }
        }, 20L * 5, 20L * 60 * 5);
    }

    @Override
    public boolean onCommand(CommandSender sender, Command command, String label, String[] args) {
        if (!(sender instanceof Player)) {
            return true;
        }
        final Player player = (Player) sender;
        if (args.length > 0 && "whois".equalsIgnoreCase(args[0])) {
            final String target = args.length > 1 ? args[1] : player.getName();
            Player online = Bukkit.getPlayerExact(target);
            final String onlineUuid = online != null ? online.getUniqueId().toString() : null;
            Bukkit.getScheduler().runTaskAsynchronously(this, new Runnable() {
                @Override
                public void run() {
                    whoisPlayer(player, target, onlineUuid);
                }
            });
            return true;
        }
        if (args.length > 0 && "reload".equalsIgnoreCase(args[0])) {
            reloadConfig();
            reloadLocalConnector();
            Bukkit.getScheduler().runTaskAsynchronously(this, new Runnable() {
                @Override
                public void run() {
                    refreshRemoteConfigAsync();
                    Bukkit.getScheduler().runTask(McWebConnectorLegacyPlugin.this, new Runnable() {
                        @Override
                        public void run() {
                            sender.sendMessage("McWeb config reloaded.");
                        }
                    });
                }
            });
            return true;
        }
        if (linkCommandConfig.isLinkAction(args.length > 0 ? args[0] : null)) {
            final String uuid = player.getUniqueId().toString();
            final String username = player.getName();
            Bukkit.getScheduler().runTaskAsynchronously(this, new Runnable() {
                @Override
                public void run() {
                    linkPlayer(player, uuid, username);
                }
            });
            return true;
        }
        sender.sendMessage(linkCommandConfig.usageHint());
        return true;
    }

    private void linkPlayer(final Player player, final String uuid, final String username) {
        try {
            String code = LinkCodes.generateCode(8);
            JsonObject body = new JsonObject();
            body.addProperty("uuid", uuid);
            body.addProperty("username", username);
            body.addProperty("platform", "java");
            body.addProperty("code_digest", LinkCodes.digestCode(code));
            JsonObject response = client.post("link_codes", body);
            String outboundCode = LinkResponseHelper.resolveCode(response, code);
            String url = response.has("link_url") ? response.get("link_url").getAsString() : getConfig().getString("website-url") + "/app/minecraft/link";
            String template = message("link_code", "Bind code: {code} - visit {url}");
            String outbound = template.replace("{code}", outboundCode).replace("{url}", url);
            Bukkit.getScheduler().runTask(this, new Runnable() {
                @Override
                public void run() {
                    player.sendMessage(outbound);
                }
            });
        } catch (Exception ex) {
            getLogger().log(Level.WARNING, "link failed", ex);
            final String failed = message("link_failed", "Failed to generate bind code.");
            Bukkit.getScheduler().runTask(this, new Runnable() {
                @Override
                public void run() {
                    player.sendMessage(failed);
                }
            });
        }
    }

    private void whoisPlayer(Player requester, String targetName, String onlineUuid) {
        try {
            JsonObject body = new JsonObject();
            body.addProperty("username", targetName);
            body.addProperty("platform", "java");
            if (onlineUuid != null) {
                body.addProperty("uuid", onlineUuid);
            }
            JsonObject response = client.post("whois", body);
            final java.util.List<String> lines = WhoisDisplayHelper.displayLines(response);
            Bukkit.getScheduler().runTask(this, new Runnable() {
                @Override
                public void run() {
                    for (String line : lines) {
                        requester.sendMessage(line);
                    }
                }
            });
        } catch (Exception ex) {
            Bukkit.getScheduler().runTask(this, new Runnable() {
                @Override
                public void run() {
                    requester.sendMessage(WhoisDisplayHelper.lookupFailedMessage(remoteConfig));
                }
            });
        }
    }

    private void executeTask(JsonObject task, TaskPoller.Completion completion) {
        String taskType = task.get("task_type").getAsString();
        JsonObject payload = task.has("payload") && task.get("payload").isJsonObject()
                ? task.getAsJsonObject("payload")
                : new JsonObject();

        if ("broadcast_announcement".equals(taskType)) {
            final String text = payload.has("message") ? payload.get("message").getAsString() : payload.has("title") ? payload.get("title").getAsString() : "";
            Bukkit.getScheduler().runTask(this, new Runnable() {
                @Override
                public void run() {
                    Bukkit.broadcastMessage(text);
                    completion.succeed("announcement broadcast");
                }
            });
            return;
        }

        if ("run_commands".equals(taskType) || "deliver_item".equals(taskType)) {
            if (!payload.has("commands")) {
                completion.fail("missing commands payload");
                return;
            }
            final JsonArray commands = payload.getAsJsonArray("commands");
            Bukkit.getScheduler().runTask(this, new Runnable() {
                @Override
                public void run() {
                    try {
                        for (int j = 0; j < commands.size(); j++) {
                            Bukkit.dispatchCommand(Bukkit.getConsoleSender(), commands.get(j).getAsString());
                        }
                        completion.succeed("commands executed");
                    } catch (Exception ex) {
                        completion.fail("command execution failed");
                    }
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

    private void syncPresence(final Player player, final String eventName, final boolean firstJoin) {
        final String uuid = player.getUniqueId().toString();
        final String username = player.getName();
        final String serverId = getConfig().getString("server-id", "");
        final JsonObject skinData = new JsonObject();
        appendSkinProperties(player, skinData);
        final JsonArray profileFields = bridges.registry.collectProfileFields(username, remoteBridgeConfig);
        final JsonArray permissionGroups = bridges.registry.collectPermissionGroups(username, remoteBridgeConfig);

        Bukkit.getScheduler().runTaskAsynchronously(this, new Runnable() {
            @Override
            public void run() {
                try {
                    java.util.ArrayList<java.util.UUID> onlineIds = new java.util.ArrayList<java.util.UUID>();
                    for (Player online : Bukkit.getOnlinePlayers()) {
                        onlineIds.add(online.getUniqueId());
                    }
                    JsonObject presenceBody = new JsonObject();
                    presenceBody.addProperty("uuid", uuid);
                    presenceBody.addProperty("username", username);
                    presenceBody.addProperty("platform", "java");
                    presenceBody.addProperty("event", eventName);
                    presenceBody.add("online_player_uuids", OnlinePlayerRoster.fromUuids(onlineIds));
                    copySkinProperties(skinData, presenceBody);
                    client.post("presence", presenceBody);

                    PresenceSync.syncProfileFields(client, getLogger(), uuid, username, profileFields);
                    PresenceSync.syncPermissionGroups(client, getLogger(), uuid, username, permissionGroups, "luckperms");

                    JsonObject eventPayload = new JsonObject();
                    eventPayload.addProperty("uuid", uuid);
                    eventPayload.addProperty("username", username);
                    eventPayload.addProperty("platform", "java");
                    eventPayload.addProperty("server_id", serverId);
                    ConnectorEvents.post(
                            client,
                            getLogger(),
                            eventName,
                            eventName + "-" + uuid + "-" + System.currentTimeMillis(),
                            eventPayload
                    );
                    if (firstJoin) {
                        ConnectorEvents.post(
                                client,
                                getLogger(),
                                "player.first_join",
                                "first-join-" + uuid,
                                eventPayload
                        );
                    }
                } catch (Exception ex) {
                    getLogger().log(Level.FINE, "presence sync failed", ex);
                }
            }
        });
    }

    private static void copySkinProperties(JsonObject from, JsonObject to) {
        if (from.has("skin_texture")) {
            to.addProperty("skin_texture", from.get("skin_texture").getAsString());
        }
        if (from.has("skin_model")) {
            to.addProperty("skin_model", from.get("skin_model").getAsString());
        }
    }

    private void appendSkinProperties(Player player, JsonObject body) {
        try {
            Object craftPlayer = Class.forName("org.bukkit.craftbukkit.entity.CraftPlayer").cast(player);
            Object profile = craftPlayer.getClass().getMethod("getProfile").invoke(craftPlayer);
            if (profile == null) {
                return;
            }
            Object properties = profile.getClass().getMethod("getProperties").invoke(profile);
            if (properties == null) {
                return;
            }
            Object textures = properties.getClass().getMethod("get", Object.class).invoke(properties, "textures");
            if (textures == null) {
                return;
            }
            java.util.Iterator<?> iterator = ((Iterable<?>) textures).iterator();
            if (!iterator.hasNext()) {
                return;
            }
            Object property = iterator.next();
            String value = String.valueOf(property.getClass().getMethod("getValue").invoke(property));
            String decoded = new String(java.util.Base64.getDecoder().decode(value));
            JsonObject parsed = new com.google.gson.JsonParser().parse(decoded).getAsJsonObject();
            if (parsed.has("textures") && parsed.getAsJsonObject("textures").has("SKIN")) {
                JsonObject skin = parsed.getAsJsonObject("textures").getAsJsonObject("SKIN");
                if (skin.has("url")) {
                    body.addProperty("skin_texture", skin.get("url").getAsString());
                }
                if (skin.has("metadata") && skin.getAsJsonObject("metadata").has("model")) {
                    body.addProperty("skin_model", skin.getAsJsonObject("metadata").get("model").getAsString().toLowerCase());
                }
            }
        } catch (Exception ignored) {
        }
    }

    private void sendHeartbeat() {
        try {
            final JsonObject body = buildHeartbeatBody();
            Bukkit.getScheduler().runTaskAsynchronously(this, new Runnable() {
                @Override
                public void run() {
                    try {
                        client.post("heartbeat", body);
                    } catch (Exception ex) {
                        getLogger().log(Level.FINE, "heartbeat failed", ex);
                    }
                }
            });
        } catch (Exception ex) {
            getLogger().log(Level.FINE, "heartbeat collection failed", ex);
        }
    }

    private JsonObject buildHeartbeatBody() {
        JsonObject body = new JsonObject();
        java.util.ArrayList<java.util.UUID> onlineIds = new java.util.ArrayList<java.util.UUID>();
        for (Player online : Bukkit.getOnlinePlayers()) {
            onlineIds.add(online.getUniqueId());
        }
        body.addProperty("online_players", Bukkit.getOnlinePlayers().size());
        body.add("online_player_uuids", OnlinePlayerRoster.fromUuids(onlineIds));
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
        return body;
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

    private void reloadLocalConnector() {
        client = new ConnectorClient(
                getConfig().getString("website-url", "http://localhost:3000"),
                getConfig().getString("server-id", ""),
                getConfig().getString("connector-secret", "")
        );
        taskPoller = new TaskPoller(client, deliveryStore, this::executeTask, getLogger());
    }

    private void refreshRemoteConfigAsync() {
        Runnable fetch = new Runnable() {
            @Override
            public void run() {
                try {
                    final JsonObject config = client.get("config");
                    final RemoteBridgeConfig bridgeConfig = RemoteBridgeConfig.from(config);
                    final LinkCommandConfig linkConfig = LinkCommandConfig.from(config);
                    Bukkit.getScheduler().runTask(McWebConnectorLegacyPlugin.this, new Runnable() {
                        @Override
                        public void run() {
                            applyRemoteConfig(config, bridgeConfig, linkConfig);
                        }
                    });
                } catch (Exception ex) {
                    getLogger().log(Level.FINE, "config fetch failed", ex);
                }
            }
        };
        if (Bukkit.isPrimaryThread()) {
            Bukkit.getScheduler().runTaskAsynchronously(this, fetch);
        } else {
            fetch.run();
        }
    }

    private void applyRemoteConfig(JsonObject config, RemoteBridgeConfig bridgeConfig, LinkCommandConfig linkConfig) {
        remoteConfig = config;
        remoteBridgeConfig = bridgeConfig;
        linkCommandConfig = linkConfig;
        bridges.applyRemoteConfig(remoteBridgeConfig);
        applyLinkCommandAliases();
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
