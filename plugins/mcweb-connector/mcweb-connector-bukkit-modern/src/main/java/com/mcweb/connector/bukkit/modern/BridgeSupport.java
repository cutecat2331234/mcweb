package com.mcweb.connector.bukkit.modern;

import com.mcweb.connector.common.BridgeProvider;
import com.mcweb.connector.common.BridgeRegistry;
import com.mcweb.connector.common.RemoteBridgeConfig;
import org.bukkit.Bukkit;
import org.bukkit.plugin.java.JavaPlugin;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

final class BridgeSupport {
    static final class Holder {
        final BridgeRegistry registry;
        private final PlaceholderApiBridge placeholderApi;

        Holder(BridgeRegistry registry, PlaceholderApiBridge placeholderApi) {
            this.registry = registry;
            this.placeholderApi = placeholderApi;
        }

        void applyRemoteConfig(RemoteBridgeConfig config) {
            if (placeholderApi != null && config != null && !config.bridgePlaceholders().isEmpty()) {
                placeholderApi.setPlaceholders(config.bridgePlaceholders());
            }
        }
    }

    private BridgeSupport() {}

    static Holder create(JavaPlugin plugin) {
        BridgeRegistry registry = new BridgeRegistry();
        PlaceholderApiBridge placeholderApi = null;
        if (Bukkit.getPluginManager().getPlugin("PlaceholderAPI") != null) {
            placeholderApi = new PlaceholderApiBridge(plugin);
            registry.register(placeholderApi);
        }
        if (Bukkit.getPluginManager().getPlugin("LuckPerms") != null) {
            registry.register(new LuckPermsBridge());
        }
        if (Bukkit.getPluginManager().getPlugin("Vault") != null) {
            registry.register(new VaultBridge());
        }
        return new Holder(registry, placeholderApi);
    }

    static final class PlaceholderApiBridge implements BridgeProvider {
        private final JavaPlugin plugin;
        private volatile List<String> placeholders = Collections.emptyList();

        PlaceholderApiBridge(JavaPlugin plugin) {
            this.plugin = plugin;
        }

        void setPlaceholders(List<String> values) {
            placeholders = values == null ? Collections.<String>emptyList() : new ArrayList<String>(values);
        }

        public String name() { return "placeholderapi"; }

        public boolean isAvailable() {
            return Bukkit.getPluginManager().getPlugin("PlaceholderAPI") != null;
        }

        public List<FieldValue> profileFields(String playerName) {
            List<String> active = placeholders.isEmpty()
                    ? plugin.getConfig().getStringList("bridge-placeholders")
                    : placeholders;
            List<FieldValue> values = new ArrayList<FieldValue>();
            try {
                Class<?> api = Class.forName("me.clip.placeholderapi.PlaceholderAPI");
                for (String placeholder : active) {
                    Object result = api.getMethod("setPlaceholders", org.bukkit.OfflinePlayer.class, String.class)
                            .invoke(null, Bukkit.getOfflinePlayer(playerName), placeholder);
                    values.add(new FieldValue(placeholder.replace("%", ""), String.valueOf(result)));
                }
            } catch (Exception ignored) {
            }
            return values;
        }

        public List<PermissionGroup> permissionGroups(String playerName) {
            return Collections.emptyList();
        }
    }

    static final class LuckPermsBridge implements BridgeProvider {
        public String name() { return "luckperms"; }
        public boolean isAvailable() { return true; }

        public List<FieldValue> profileFields(String playerName) {
            return Collections.emptyList();
        }

        public List<PermissionGroup> permissionGroups(String playerName) {
            List<PermissionGroup> groups = new ArrayList<PermissionGroup>();
            try {
                Class<?> provider = Class.forName("net.luckperms.api.LuckPermsProvider");
                Object api = provider.getMethod("get").invoke(null);
                Object userManager = api.getClass().getMethod("getUserManager").invoke(api);
                Object user = userManager.getClass().getMethod("getUser", java.util.UUID.class)
                        .invoke(userManager, Bukkit.getOfflinePlayer(playerName).getUniqueId());
                if (user != null) {
                    Object primary = user.getClass().getMethod("getPrimaryGroup").invoke(user);
                    groups.add(new PermissionGroup(String.valueOf(primary), String.valueOf(primary), 100));
                }
            } catch (Exception ignored) {
            }
            return groups;
        }
    }

    static final class VaultBridge implements BridgeProvider {
        public String name() { return "vault"; }
        public boolean isAvailable() { return true; }

        public List<FieldValue> profileFields(String playerName) {
            List<FieldValue> values = new ArrayList<FieldValue>();
            try {
                Class<?> economyClass = Class.forName("net.milkbowl.vault.economy.Economy");
                Object registration = Bukkit.getServicesManager().getRegistration(economyClass);
                if (registration != null) {
                    Object economy = registration.getClass().getMethod("getProvider").invoke(registration);
                    double balance = (Double) economyClass.getMethod("getBalance", String.class).invoke(economy, playerName);
                    values.add(new FieldValue("vault_balance", String.valueOf(balance)));
                }
            } catch (Exception ignored) {
            }
            return values;
        }

        public List<PermissionGroup> permissionGroups(String playerName) {
            return Collections.emptyList();
        }
    }
}
