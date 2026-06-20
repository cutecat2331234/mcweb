package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.HashSet;
import java.util.List;
import java.util.Set;

public final class RemoteBridgeConfig {
    public enum BridgePolicy {
        ALL,
        ONLY_LISTED,
        NONE
    }

    private final BridgePolicy bridgePolicy;
    private final Set<String> enabledBridges;
    private final List<String> bridgePlaceholders;
    private final boolean bridgePlaceholdersConfigured;

    public RemoteBridgeConfig(
            BridgePolicy bridgePolicy,
            Set<String> enabledBridges,
            List<String> bridgePlaceholders,
            boolean bridgePlaceholdersConfigured
    ) {
        this.bridgePolicy = bridgePolicy;
        this.enabledBridges = enabledBridges;
        this.bridgePlaceholders = bridgePlaceholders;
        this.bridgePlaceholdersConfigured = bridgePlaceholdersConfigured;
    }

    public static RemoteBridgeConfig from(JsonObject config) {
        if (config == null) {
            return new RemoteBridgeConfig(
                    BridgePolicy.ALL,
                    Collections.<String>emptySet(),
                    Collections.<String>emptyList(),
                    false
            );
        }

        BridgePolicy bridgePolicy = BridgePolicy.ALL;
        Set<String> bridges = new HashSet<String>();
        if (config.has("bridges") && config.get("bridges").isJsonArray()) {
            JsonArray array = config.getAsJsonArray("bridges");
            if (array.size() == 0) {
                bridgePolicy = BridgePolicy.NONE;
            } else {
                bridgePolicy = BridgePolicy.ONLY_LISTED;
                for (int i = 0; i < array.size(); i++) {
                    JsonElement element = array.get(i);
                    if (element.isJsonPrimitive()) {
                        bridges.add(element.getAsString().trim().toLowerCase());
                    }
                }
            }
        }

        List<String> placeholders = new ArrayList<String>();
        boolean placeholdersConfigured = config.has("bridge_placeholders") && config.get("bridge_placeholders").isJsonArray();
        if (placeholdersConfigured) {
            JsonArray array = config.getAsJsonArray("bridge_placeholders");
            for (int i = 0; i < array.size(); i++) {
                JsonElement element = array.get(i);
                if (element.isJsonPrimitive()) {
                    String value = element.getAsString().trim();
                    if (!value.isEmpty()) {
                        placeholders.add(value);
                    }
                }
            }
        }

        return new RemoteBridgeConfig(bridgePolicy, bridges, placeholders, placeholdersConfigured);
    }

    public boolean bridgeEnabled(String name) {
        switch (bridgePolicy) {
            case NONE:
                return false;
            case ONLY_LISTED:
                return enabledBridges.contains(name.toLowerCase());
            case ALL:
            default:
                return true;
        }
    }

    public List<String> bridgePlaceholders() {
        return bridgePlaceholders;
    }

    public boolean bridgePlaceholdersConfigured() {
        return bridgePlaceholdersConfigured;
    }
}
