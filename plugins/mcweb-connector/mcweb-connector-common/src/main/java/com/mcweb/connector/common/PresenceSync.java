package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.io.IOException;
import java.util.logging.Level;
import java.util.logging.Logger;

public final class PresenceSync {
    private PresenceSync() {
    }

    public static void sync(
            ConnectorClient client,
            Logger logger,
            String uuid,
            String username,
            String platform,
            String serverId,
            String eventName,
            boolean firstJoin,
            JsonArray onlinePlayerUuids
    ) {
        JsonObject eventPayload = basePayload(uuid, username, platform, serverId);

        try {
            JsonObject presenceBody = basePayload(uuid, username, platform, serverId);
            presenceBody.addProperty("event", eventName);
            if (onlinePlayerUuids != null) {
                presenceBody.add("online_player_uuids", onlinePlayerUuids);
            }
            client.post("presence", presenceBody);
            McWebMembershipSync.refresh(client, logger, username, uuid, platform);
        } catch (IOException ex) {
            logger.log(Level.FINE, "presence sync failed", ex);
        }

        String eventId = eventName + "-" + uuid + "-" + System.currentTimeMillis();
        ConnectorEvents.post(client, logger, eventName, eventId, eventPayload);
        if (firstJoin) {
            ConnectorEvents.post(client, logger, "player.first_join", "first-join-" + uuid, eventPayload);
        }
    }

    public static void sync(
            ConnectorClient client,
            Logger logger,
            String uuid,
            String username,
            String platform,
            String serverId,
            String eventName,
            boolean firstJoin
    ) {
        sync(client, logger, uuid, username, platform, serverId, eventName, firstJoin, null);
    }

    public static void syncProfileFields(
            ConnectorClient client,
            Logger logger,
            String uuid,
            String username,
            BridgeRegistry bridges,
            RemoteBridgeConfig remoteBridgeConfig
    ) {
        if (bridges == null) {
            return;
        }
        syncProfileFields(client, logger, uuid, username, bridges.collectProfileFields(username, remoteBridgeConfig));
    }

    public static void syncProfileFields(
            ConnectorClient client,
            Logger logger,
            String uuid,
            String username,
            com.google.gson.JsonArray fields
    ) {
        if (fields == null) {
            return;
        }
        try {
            JsonObject body = new JsonObject();
            body.addProperty("uuid", uuid);
            body.addProperty("username", username);
            body.add("fields", fields);
            client.post("profile_fields", body);
        } catch (IOException ex) {
            logger.log(Level.FINE, "profile_fields sync failed", ex);
        }
    }

    public static void syncPermissionGroups(
            ConnectorClient client,
            Logger logger,
            String uuid,
            String username,
            BridgeRegistry bridges,
            RemoteBridgeConfig remoteBridgeConfig,
            String source
    ) {
        if (bridges == null) {
            return;
        }
        syncPermissionGroups(
                client,
                logger,
                uuid,
                username,
                bridges.collectPermissionGroups(username, remoteBridgeConfig),
                source
        );
    }

    public static void syncPermissionGroups(
            ConnectorClient client,
            Logger logger,
            String uuid,
            String username,
            com.google.gson.JsonArray groups,
            String source
    ) {
        if (groups == null) {
            return;
        }
        try {
            JsonObject body = new JsonObject();
            body.addProperty("uuid", uuid);
            body.addProperty("username", username);
            body.addProperty("source", source);
            body.add("groups", groups);
            client.post("permission_groups", body);
        } catch (IOException ex) {
            logger.log(Level.FINE, "permission_groups sync failed", ex);
        }
    }

    private static JsonObject basePayload(String uuid, String username, String platform, String serverId) {
        JsonObject body = new JsonObject();
        body.addProperty("uuid", uuid);
        body.addProperty("username", username);
        body.addProperty("platform", platform);
        if (serverId != null && !serverId.isEmpty()) {
            body.addProperty("server_id", serverId);
        }
        return body;
    }
}
