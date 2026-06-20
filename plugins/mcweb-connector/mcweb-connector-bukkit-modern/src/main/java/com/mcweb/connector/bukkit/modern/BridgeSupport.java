package com.mcweb.connector.bukkit.modern;

import com.mcweb.connector.common.BridgeProvider;
import com.mcweb.connector.common.BridgeRegistry;
import com.mcweb.connector.common.LuckPermsBridgeHelper;
import com.mcweb.connector.common.McWebBridge;
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
            if (placeholderApi == null || config == null) {
                return;
            }
            if (!config.bridgePlaceholdersConfigured()) {
                placeholderApi.clearRemotePlaceholders();
                return;
            }
            placeholderApi.setRemotePlaceholders(config.bridgePlaceholders());
        }
    }

    private BridgeSupport() {}

    static Holder create(JavaPlugin plugin) {
        BridgeRegistry registry = new BridgeRegistry();
        registry.register(new McWebBridge());
        PlaceholderApiBridge placeholderApi = null;
        if (Bukkit.getPluginManager().getPlugin("PlaceholderAPI") != null) {
            placeholderApi = new PlaceholderApiBridge(plugin);
            registry.register(placeholderApi);
            registerMcWebPlaceholders(plugin);
        }
        if (Bukkit.getPluginManager().getPlugin("LuckPerms") != null) {
            registry.register(new LuckPermsBridge(plugin));
        }
        if (Bukkit.getPluginManager().getPlugin("Vault") != null) {
            VaultBridge vaultBridge = new VaultBridge();
            if (vaultBridge.isAvailable()) {
                registry.register(vaultBridge);
            }
        }
        return new Holder(registry, placeholderApi);
    }

    static final class PlaceholderApiBridge implements BridgeProvider {
        private final JavaPlugin plugin;
        private volatile boolean remotePlaceholdersActive = false;
        private volatile List<String> placeholders = Collections.emptyList();

        PlaceholderApiBridge(JavaPlugin plugin) {
            this.plugin = plugin;
        }

        void clearRemotePlaceholders() {
            remotePlaceholdersActive = false;
            placeholders = Collections.emptyList();
        }

        void setRemotePlaceholders(List<String> values) {
            remotePlaceholdersActive = true;
            placeholders = values == null ? Collections.<String>emptyList() : new ArrayList<String>(values);
        }

        public String name() { return "placeholderapi"; }

        public boolean isAvailable() {
            return Bukkit.getPluginManager().getPlugin("PlaceholderAPI") != null;
        }

        public List<FieldValue> profileFields(String playerName) {
            List<String> active = remotePlaceholdersActive
                    ? placeholders
                    : plugin.getConfig().getStringList("bridge-placeholders");
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
        private final JavaPlugin plugin;

        LuckPermsBridge(JavaPlugin plugin) {
            this.plugin = plugin;
        }

        public String name() { return "luckperms"; }

        public boolean isAvailable() {
            try {
                Class<?> provider = Class.forName("net.luckperms.api.LuckPermsProvider");
                provider.getMethod("get").invoke(null);
                return true;
            } catch (Exception ex) {
                return false;
            }
        }

        public List<FieldValue> profileFields(String playerName) {
            return Collections.emptyList();
        }

        public List<PermissionGroup> permissionGroups(String playerName) {
            return LuckPermsBridgeHelper.permissionGroups(
                    playerName,
                    Bukkit.getOfflinePlayer(playerName).getUniqueId(),
                    plugin.getLogger()
            );
        }
    }

    static final class VaultBridge implements BridgeProvider {
        public String name() { return "vault"; }

        public boolean isAvailable() {
            try {
                Class<?> economyClass = Class.forName("net.milkbowl.vault.economy.Economy");
                return Bukkit.getServicesManager().getRegistration(economyClass) != null;
            } catch (Exception ex) {
                return false;
            }
        }

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

    private static void registerMcWebPlaceholders(JavaPlugin plugin) {
        try {
            Class<?> expansionBase = Class.forName("me.clip.placeholderapi.expansion.PlaceholderExpansion");
            Object expansion = expansionBase.getDeclaredConstructor().newInstance();
            java.lang.reflect.Method setIdentifier = expansionBase.getMethod("setIdentifier", String.class);
            setIdentifier.invoke(expansion, "mcweb");
            expansionBase.getMethod("setAuthor", String.class).invoke(expansion, "McWeb");
            expansionBase.getMethod("setVersion", String.class).invoke(expansion, plugin.getDescription().getVersion());
            expansionBase.getMethod("setCanPersist").invoke(expansion);
            java.lang.reflect.InvocationHandler handler = (proxy, method, args) -> {
                String name = method.getName();
                if ("getIdentifier".equals(name)) return "mcweb";
                if ("getAuthor".equals(name)) return "McWeb";
                if ("getVersion".equals(name)) return plugin.getDescription().getVersion();
                if ("persist".equals(name) || "canRegister".equals(name)) return true;
                if (("onRequest".equals(name) || "onPlaceholderRequest".equals(name)) && args != null && args.length >= 2) {
                    org.bukkit.OfflinePlayer player = (org.bukkit.OfflinePlayer) args[0];
                    String params = args[1] == null ? "" : String.valueOf(args[1]);
                    String playerName = player == null ? "" : player.getName();
                    return com.mcweb.connector.common.McWebBridge.resolvePlaceholder(playerName, params);
                }
                return null;
            };
            Object proxy = java.lang.reflect.Proxy.newProxyInstance(
                    expansionBase.getClassLoader(),
                    new Class<?>[] { expansionBase },
                    handler
            );
            Class<?> api = Class.forName("me.clip.placeholderapi.PlaceholderAPI");
            api.getMethod("registerExpansion", expansionBase).invoke(null, proxy);
        } catch (Exception ignored) {
        }
    }
}
