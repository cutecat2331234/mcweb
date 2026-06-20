package com.mcweb.connector.common;

import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.TimeUnit;
import java.util.logging.Logger;

public final class LuckPermsBridgeHelper {
    private LuckPermsBridgeHelper() {
    }

    public static List<BridgeProvider.PermissionGroup> permissionGroups(
            String playerName,
            UUID playerId,
            Logger logger
    ) {
        List<BridgeProvider.PermissionGroup> groups = new ArrayList<BridgeProvider.PermissionGroup>();
        try {
            Class<?> provider = Class.forName("net.luckperms.api.LuckPermsProvider");
            Object api = provider.getMethod("get").invoke(null);
            Object userManager = api.getClass().getMethod("getUserManager").invoke(api);

            Object user = loadUser(userManager, playerName, playerId);
            if (user == null) {
                return groups;
            }

            Object primary = user.getClass().getMethod("getPrimaryGroup").invoke(user);
            if (primary != null) {
                String groupName = String.valueOf(primary);
                groups.add(new BridgeProvider.PermissionGroup(groupName, groupName, 100));
            }
        } catch (Exception ex) {
            if (logger != null) {
                logger.fine("LuckPerms bridge unavailable: " + ex.getMessage());
            }
        }
        return groups;
    }

    private static Object loadUser(Object userManager, String playerName, UUID playerId) throws Exception {
        UUID uuid = playerId;
        if (uuid == null) {
            uuid = resolveUuid(userManager, playerName);
        }
        if (uuid == null) {
            return null;
        }

        Object user = unwrapOptional(
                userManager.getClass().getMethod("getUser", UUID.class).invoke(userManager, uuid)
        );
        if (user != null) {
            return user;
        }

        Object loaded = userManager.getClass().getMethod("loadUser", UUID.class).invoke(userManager, uuid);
        if (loaded instanceof java.util.concurrent.CompletableFuture) {
            loaded = ((java.util.concurrent.CompletableFuture<?>) loaded).get(5, TimeUnit.SECONDS);
        }
        return unwrapOptional(loaded);
    }

    private static UUID resolveUuid(Object userManager, String playerName) throws Exception {
        Object result = userManager.getClass()
                .getMethod("lookupUniqueId", String.class)
                .invoke(userManager, playerName);
        if (result instanceof java.util.concurrent.CompletableFuture) {
            result = ((java.util.concurrent.CompletableFuture<?>) result).get(5, TimeUnit.SECONDS);
        }
        return result instanceof UUID ? (UUID) result : null;
    }

    private static Object unwrapOptional(Object value) {
        if (value instanceof java.util.Optional) {
            return ((java.util.Optional<?>) value).orElse(null);
        }
        return value;
    }
}
