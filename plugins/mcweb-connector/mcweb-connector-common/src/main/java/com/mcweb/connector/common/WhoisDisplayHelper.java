package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;

public final class WhoisDisplayHelper {
    private WhoisDisplayHelper() {
    }

    public static List<String> displayLines(JsonObject response) {
        if (response == null) {
            return Collections.emptyList();
        }

        if (response.has("whois_lines") && response.get("whois_lines").isJsonArray()) {
            JsonArray lines = response.getAsJsonArray("whois_lines");
            List<String> localized = new ArrayList<String>();
            for (int i = 0; i < lines.size(); i++) {
                if (!lines.get(i).isJsonNull()) {
                    localized.add(lines.get(i).getAsString());
                }
            }
            if (!localized.isEmpty()) {
                return localized;
            }
        }

        List<String> fallback = new ArrayList<String>();
        if (response.has("linked") && response.get("linked").getAsBoolean()) {
            if (response.has("website_username")) {
                fallback.add("Website: " + response.get("website_username").getAsString());
            }
            if (response.has("trust_level_label")) {
                fallback.add("Trust: " + response.get("trust_level_label").getAsString());
            }
            if (response.has("membership_labels") && !response.get("membership_labels").getAsString().isEmpty()) {
                fallback.add("Membership: " + response.get("membership_labels").getAsString());
            }
            if (response.has("membership_expires_at") && !response.get("membership_expires_at").getAsString().isEmpty()) {
                fallback.add("Membership expires: " + response.get("membership_expires_at").getAsString());
            }
            return fallback;
        }

        fallback.add(response.has("message")
                ? response.get("message").getAsString()
                : "Player not linked.");
        return fallback;
    }

    public static String lookupFailedMessage(JsonObject remoteConfig) {
        if (remoteConfig != null
                && remoteConfig.has("messages")
                && remoteConfig.getAsJsonObject("messages").has("whois_failed")) {
            return remoteConfig.getAsJsonObject("messages").get("whois_failed").getAsString();
        }
        return "Whois lookup failed.";
    }
}
