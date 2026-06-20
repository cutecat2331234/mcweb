package com.mcweb.connector.common;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class McWebBridge implements BridgeProvider {
    public String name() {
        return "mcweb";
    }

    public boolean isAvailable() {
        return true;
    }

    public List<FieldValue> profileFields(String playerName) {
        PlayerMembershipCache.Entry entry = PlayerMembershipCache.get(playerName);
        return Arrays.asList(
                new FieldValue("mcweb_membership", entry.labels),
                new FieldValue("mcweb_membership_primary", entry.primary),
                new FieldValue("mcweb_membership_expires_at", entry.expiresAt)
        );
    }

    public List<PermissionGroup> permissionGroups(String playerName) {
        return Collections.emptyList();
    }

    public static String resolvePlaceholder(String playerName, String params) {
        PlayerMembershipCache.Entry entry = PlayerMembershipCache.get(playerName);
        if (params == null || params.isEmpty() || "membership".equalsIgnoreCase(params) || "membership_labels".equalsIgnoreCase(params)) {
            return entry.labels;
        }
        if ("membership_primary".equalsIgnoreCase(params)) {
            return entry.primary;
        }
        if ("membership_expires_at".equalsIgnoreCase(params)) {
            return entry.expiresAt;
        }
        return "";
    }
}
