package com.mcweb.connector.common;

import org.junit.jupiter.api.Test;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;

class ConnectorSignerTest {
    @Test
    void signProducesStableHmacSha256Hex() {
        String signature = ConnectorSigner.sign("test-secret", "{\"ok\":true}", 1_700_000_000L);
        assertEquals(64, signature.length());
        assertEquals(signature, ConnectorSigner.sign("test-secret", "{\"ok\":true}", 1_700_000_000L));
    }

    @Test
    void signChangesWhenPayloadOrTimestampChanges() {
        String base = ConnectorSigner.sign("test-secret", "{}", 1_700_000_000L);
        assertNotEquals(base, ConnectorSigner.sign("test-secret", "{\"a\":1}", 1_700_000_000L));
        assertNotEquals(base, ConnectorSigner.sign("test-secret", "{}", 1_700_000_001L));
        assertNotEquals(base, ConnectorSigner.sign("other-secret", "{}", 1_700_000_000L));
    }
}
