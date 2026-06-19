package com.mcweb.connector.common;

import com.google.gson.JsonObject;

import java.io.IOException;
import java.util.logging.Level;
import java.util.logging.Logger;

public final class ConnectorEvents {
    private ConnectorEvents() {
    }

    public static void post(ConnectorClient client, Logger logger, String eventKey, String eventId, JsonObject payload) {
        try {
            JsonObject body = new JsonObject();
            body.addProperty("event", eventKey);
            body.addProperty("event_id", eventId);
            if (payload != null) {
                copyIfPresent(payload, body, "uuid");
                copyIfPresent(payload, body, "username");
                copyIfPresent(payload, body, "platform");
                copyIfPresent(payload, body, "player_id");
                copyIfPresent(payload, body, "server_id");
                body.add("payload", payload);
            } else {
                body.add("payload", new JsonObject());
            }
            client.post("events", body);
        } catch (IOException ex) {
            logger.log(Level.FINE, "event post failed: " + eventKey, ex);
        }
    }

    private static void copyIfPresent(JsonObject source, JsonObject target, String key) {
        if (source.has(key) && !source.get(key).isJsonNull()) {
            target.add(key, source.get(key));
        }
    }
}
