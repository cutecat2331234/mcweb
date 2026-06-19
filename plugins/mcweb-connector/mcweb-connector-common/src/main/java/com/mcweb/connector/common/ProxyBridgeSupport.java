package com.mcweb.connector.common;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.UUID;
import java.util.logging.Logger;

public final class ProxyBridgeSupport {
    private ProxyBridgeSupport() {
    }

    public static BridgeRegistry create(Logger logger) {
        BridgeRegistry registry = new BridgeRegistry();
        registry.register(new LuckPermsBridge(logger));
        return registry;
    }

    private static final class LuckPermsBridge implements BridgeProvider {
        private final Logger logger;

        LuckPermsBridge(Logger logger) {
            this.logger = logger;
        }

        public String name() {
            return "luckperms";
        }

        public boolean isAvailable() {
            try {
                Class.forName("net.luckperms.api.LuckPermsProvider");
                return true;
            } catch (ClassNotFoundException ex) {
                return false;
            }
        }

        public List<FieldValue> profileFields(String playerName) {
            return Collections.emptyList();
        }

        public List<PermissionGroup> permissionGroups(String playerName) {
            List<PermissionGroup> groups = new ArrayList<PermissionGroup>();
            try {
                Class<?> provider = Class.forName("net.luckperms.api.LuckPermsProvider");
                Object api = provider.getMethod("get").invoke(null);
                Object userManager = api.getClass().getMethod("getUserManager").invoke(api);
                Object user = userManager.getClass().getMethod("getUser", String.class).invoke(userManager, playerName.toLowerCase());
                if (user == null) {
                    Object uuid = userManager.getClass().getMethod("lookupUniqueId", String.class).invoke(userManager, playerName);
                    if (uuid != null) {
                        user = userManager.getClass().getMethod("loadUser", UUID.class).invoke(userManager, uuid);
                        if (user instanceof java.util.concurrent.CompletableFuture) {
                            user = ((java.util.concurrent.CompletableFuture<?>) user).get();
                        }
                    }
                }
                if (user != null) {
                    Object primary = user.getClass().getMethod("getPrimaryGroup").invoke(user);
                    groups.add(new PermissionGroup(String.valueOf(primary), String.valueOf(primary), 100));
                }
            } catch (Exception ex) {
                logger.fine("LuckPerms bridge unavailable: " + ex.getMessage());
            }
            return groups;
        }
    }
}
