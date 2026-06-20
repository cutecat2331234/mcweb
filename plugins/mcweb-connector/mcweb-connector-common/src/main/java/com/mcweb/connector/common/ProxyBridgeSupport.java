package com.mcweb.connector.common;

import java.util.Collections;
import java.util.List;
import java.util.logging.Logger;

public final class ProxyBridgeSupport {
    private ProxyBridgeSupport() {
    }

    public static BridgeRegistry create(Logger logger) {
        BridgeRegistry registry = new BridgeRegistry();
        registry.register(new LuckPermsBridge(logger));
        return registry;
    }

    private static final class LuckPermsBridge implements BridgeProvider {
        private final Logger logger;

        LuckPermsBridge(Logger logger) {
            this.logger = logger;
        }

        public String name() {
            return "luckperms";
        }

        public boolean isAvailable() {
            try {
                Class<?> provider = Class.forName("net.luckperms.api.LuckPermsProvider");
                provider.getMethod("get").invoke(null);
                return true;
            } catch (Exception ex) {
                return false;
            }
        }

        public List<FieldValue> profileFields(String playerName) {
            return Collections.emptyList();
        }

        public List<PermissionGroup> permissionGroups(String playerName) {
            return LuckPermsBridgeHelper.permissionGroups(playerName, null, logger);
        }
    }
}
