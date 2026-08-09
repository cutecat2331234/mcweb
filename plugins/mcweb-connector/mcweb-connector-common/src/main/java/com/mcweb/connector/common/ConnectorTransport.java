package com.mcweb.connector.common;

import com.google.gson.JsonObject;

import java.io.IOException;

/**
 * The HTTP operations used by the connector polling loop.
 *
 * Keeping this contract independent from the concrete signed client makes the
 * delivery protocol testable without weakening or bypassing request signing.
 */
public interface ConnectorTransport {
    JsonObject post(String endpoint, JsonObject body) throws IOException;

    JsonObject get(String endpoint) throws IOException;
}
