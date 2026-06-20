package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.util.ArrayList;
import java.util.List;
import java.util.logging.Logger;

public final class BridgeRegistry {
    private final List<BridgeProvider> providers = new ArrayList<BridgeProvider>();

    public void register(BridgeProvider provider) {
        providers.add(provider);
    }

    public JsonArray collectProfileFields(String playerName) {
        return collectProfileFields(playerName, null);
    }

    public JsonArray collectProfileFields(String playerName, RemoteBridgeConfig remoteConfig) {
        JsonArray fields = new JsonArray();
        for (BridgeProvider provider : providers) {
            if (remoteConfig != null && !remoteConfig.bridgeEnabled(provider.name())) {
                continue;
            }
            if (!provider.isAvailable()) {
                continue;
            }
            try {
                List<BridgeProvider.FieldValue> profileFields = provider.profileFields(playerName);
                if (profileFields == null) {
                    continue;
                }
                for (BridgeProvider.FieldValue field : profileFields) {
                    JsonObject entry = new JsonObject();
                    entry.addProperty("key", field.key);
                    entry.addProperty("value", field.value);
                    fields.add(entry);
                }
            } catch (Exception ex) {
                Logger.getLogger("McWebConnector").warning("Bridge failed: " + provider.name() + " - " + ex.getMessage());
            }
        }
        return fields;
    }

    public JsonArray collectPermissionGroups(String playerName) {
        return collectPermissionGroups(playerName, null);
    }

    public JsonArray collectPermissionGroups(String playerName, RemoteBridgeConfig remoteConfig) {
        JsonArray groups = new JsonArray();
        for (BridgeProvider provider : providers) {
            if (remoteConfig != null && !remoteConfig.bridgeEnabled(provider.name())) {
                continue;
            }
            if (!provider.isAvailable()) {
                continue;
            }
            try {
                List<BridgeProvider.PermissionGroup> permissionGroups = provider.permissionGroups(playerName);
                if (permissionGroups == null) {
                    continue;
                }
                for (BridgeProvider.PermissionGroup group : permissionGroups) {
                    JsonObject entry = new JsonObject();
                    entry.addProperty("key", group.key);
                    entry.addProperty("label", group.label);
                    entry.addProperty("weight", group.weight);
                    groups.add(entry);
                }
            } catch (Exception ex) {
                Logger.getLogger("McWebConnector").warning("Bridge failed: " + provider.name() + " - " + ex.getMessage());
            }
        }
        return groups;
    }
}
