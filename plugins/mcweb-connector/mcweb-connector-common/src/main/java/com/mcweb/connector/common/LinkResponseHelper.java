package com.mcweb.connector.common;

import com.google.gson.JsonObject;

import java.io.IOException;

public final class LinkResponseHelper {
    private LinkResponseHelper() {
    }

    public static String requireCode(JsonObject response) throws IOException {
        if (response == null || !response.has("code") || response.get("code").isJsonNull()) {
            throw new IOException("missing link code in response");
        }
        return response.get("code").getAsString();
    }

    public static String resolveCode(JsonObject response, String localCode) throws IOException {
        if (localCode != null && !localCode.isEmpty()) {
            return localCode;
        }
        return requireCode(response);
    }
}
