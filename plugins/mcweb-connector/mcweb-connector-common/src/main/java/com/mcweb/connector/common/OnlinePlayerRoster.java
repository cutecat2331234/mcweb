package com.mcweb.connector.common;

import com.google.gson.JsonArray;

import java.util.Collection;
import java.util.UUID;

public final class OnlinePlayerRoster {
    private OnlinePlayerRoster() {
    }

    public static JsonArray fromUuids(Collection<UUID> uuids) {
        JsonArray array = new JsonArray();
        if (uuids == null) {
            return array;
        }
        for (UUID uuid : uuids) {
            if (uuid != null) {
                array.add(uuid.toString());
            }
        }
        return array;
    }

    public static JsonArray fromStringUuids(Collection<String> uuids) {
        JsonArray array = new JsonArray();
        if (uuids == null) {
            return array;
        }
        for (String uuid : uuids) {
            if (uuid != null && !uuid.isEmpty()) {
                array.add(uuid);
            }
        }
        return array;
    }
}
