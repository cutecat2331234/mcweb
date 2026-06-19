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
    private final Set<String> enabledBridges;
    private final List<String> bridgePlaceholders;

    public RemoteBridgeConfig(Set<String> enabledBridges, List<String> bridgePlaceholders) {
        this.enabledBridges = enabledBridges;
        this.bridgePlaceholders = bridgePlaceholders;
    }

    public static RemoteBridgeConfig from(JsonObject config) {
        if (config == null) {
            return new RemoteBridgeConfig(Collections.<String>emptySet(), Collections.<String>emptyList());
        }

        Set<String> bridges = new HashSet<String>();
        if (config.has("bridges") && config.get("bridges").isJsonArray()) {
            JsonArray array = config.getAsJsonArray("bridges");
            for (int i = 0; i < array.size(); i++) {
                JsonElement element = array.get(i);
                if (element.isJsonPrimitive()) {
                    bridges.add(element.getAsString().trim().toLowerCase());
                }
            }
        }

        List<String> placeholders = new ArrayList<String>();
        if (config.has("bridge_placeholders") && config.get("bridge_placeholders").isJsonArray()) {
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

        return new RemoteBridgeConfig(bridges, placeholders);
    }

    public boolean bridgeEnabled(String name) {
        if (enabledBridges.isEmpty()) {
            return true;
        }
        return enabledBridges.contains(name.toLowerCase());
    }

    public List<String> bridgePlaceholders() {
        return bridgePlaceholders;
    }
}
