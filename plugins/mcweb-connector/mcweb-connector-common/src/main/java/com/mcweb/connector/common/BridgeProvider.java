package com.mcweb.connector.common;

import java.util.Collections;
import java.util.List;

public interface BridgeProvider {
    String name();

    boolean isAvailable();

    List<FieldValue> profileFields(String playerName);

    List<PermissionGroup> permissionGroups(String playerName);

    final class FieldValue {
        public final String key;
        public final String value;

        public FieldValue(String key, String value) {
            this.key = key;
            this.value = value;
        }
    }

    final class PermissionGroup {
        public final String key;
        public final String label;
        public final int weight;

        public PermissionGroup(String key, String label, int weight) {
            this.key = key;
            this.label = label;
            this.weight = weight;
        }
    }

    BridgeProvider NOOP = new BridgeProvider() {
        public String name() { return "noop"; }
        public boolean isAvailable() { return false; }
        public List<FieldValue> profileFields(String playerName) { return Collections.emptyList(); }
        public List<PermissionGroup> permissionGroups(String playerName) { return Collections.emptyList(); }
    };
}
