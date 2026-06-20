package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;

import java.util.Locale;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.ConcurrentMap;

public final class PlayerMembershipCache {
    public static final class Entry {
        public final String labels;
        public final String primary;
        public final String expiresAt;

        public Entry(String labels, String primary, String expiresAt) {
            this.labels = labels == null ? "" : labels;
            this.primary = primary == null ? "" : primary;
            this.expiresAt = expiresAt == null ? "" : expiresAt;
        }
    }

    private static final ConcurrentMap<String, Entry> CACHE = new ConcurrentHashMap<String, Entry>();

    private PlayerMembershipCache() {
    }

    public static void updateFromWhois(String username, JsonObject response) {
        if (username == null || username.isEmpty() || response == null) {
            return;
        }
        String key = username.toLowerCase(Locale.ROOT);
        if (!response.has("linked") || !response.get("linked").getAsBoolean()) {
            CACHE.remove(key);
            return;
        }

        String labels = response.has("membership_labels") ? response.get("membership_labels").getAsString() : "";
        String primary = "";
        if (response.has("memberships") && response.get("memberships").isJsonArray()) {
            JsonArray memberships = response.getAsJsonArray("memberships");
            if (memberships.size() > 0) {
                JsonElement first = memberships.get(0);
                if (first.isJsonObject() && first.getAsJsonObject().has("name")) {
                    primary = first.getAsJsonObject().get("name").getAsString();
                }
            }
        }
        if (primary.isEmpty() && response.has("membership_primary")) {
            primary = response.get("membership_primary").getAsString();
        }
        String expiresAt = response.has("membership_expires_at") ? response.get("membership_expires_at").getAsString() : "";
        CACHE.put(key, new Entry(labels, primary, expiresAt));
    }

    public static Entry get(String username) {
        if (username == null || username.isEmpty()) {
            return new Entry("", "", "");
        }
        Entry entry = CACHE.get(username.toLowerCase(Locale.ROOT));
        return entry == null ? new Entry("", "", "") : entry;
    }

    public static void clear(String username) {
        if (username == null || username.isEmpty()) {
            return;
        }
        CACHE.remove(username.toLowerCase(Locale.ROOT));
    }
}
