package com.mcweb.connector.common;

import com.google.gson.JsonObject;

import java.io.IOException;
import java.util.Arrays;
import java.util.List;
import java.util.logging.Level;
import java.util.logging.Logger;

public final class McWebMembershipSync {
    private McWebMembershipSync() {
    }

    public static void refresh(
            ConnectorClient client,
            Logger logger,
            String username,
            String uuid,
            String platform
    ) {
        if (client == null || username == null || username.isEmpty()) {
            return;
        }
        try {
            JsonObject body = new JsonObject();
            body.addProperty("username", username);
            body.addProperty("platform", platform == null ? "java" : platform);
            if (uuid != null && !uuid.isEmpty()) {
                body.addProperty("uuid", uuid);
            }
            JsonObject response = client.post("whois", body);
            PlayerMembershipCache.updateFromWhois(username, response);
        } catch (IOException ex) {
            logger.log(Level.FINE, "membership cache refresh failed", ex);
        }
    }
}
