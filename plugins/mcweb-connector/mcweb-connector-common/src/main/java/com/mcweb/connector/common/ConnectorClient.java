package com.mcweb.connector.common;

import com.google.gson.Gson;
import com.google.gson.JsonObject;
import okhttp3.*;

import java.io.IOException;
import java.util.concurrent.TimeUnit;

public final class ConnectorClient {
    private static final Gson GSON = new Gson();
    private static final MediaType JSON = MediaType.parse("application/json; charset=utf-8");

    private final String baseUrl;
    private final String serverId;
    private final String secret;
    private final OkHttpClient http;

    public ConnectorClient(String baseUrl, String serverId, String secret) {
        this.baseUrl = baseUrl.endsWith("/") ? baseUrl.substring(0, baseUrl.length() - 1) : baseUrl;
        this.serverId = serverId;
        this.secret = secret;
        this.http = new OkHttpClient.Builder()
                .connectTimeout(10, TimeUnit.SECONDS)
                .readTimeout(20, TimeUnit.SECONDS)
                .writeTimeout(20, TimeUnit.SECONDS)
                .build();
    }

    public JsonObject post(String endpoint, JsonObject body) throws IOException {
        return executeWithRetry(() -> signedPost(endpoint, body));
    }

    public JsonObject get(String endpoint) throws IOException {
        return executeWithRetry(() -> signedGet(endpoint));
    }

    private JsonObject signedPost(String endpoint, JsonObject body) throws IOException {
        String json = GSON.toJson(body);
        long timestamp = System.currentTimeMillis() / 1000L;
        String signature = sign(json, timestamp);
        Request request = new Request.Builder()
                .url(baseUrl + "/minecraft/connector/" + serverId + "/" + endpoint)
                .post(RequestBody.create(JSON, json))
                .addHeader("X-Connector-Timestamp", String.valueOf(timestamp))
                .addHeader("X-Connector-Signature", signature)
                .build();
        return parse(request);
    }

    private JsonObject signedGet(String endpoint) throws IOException {
        long timestamp = System.currentTimeMillis() / 1000L;
        String signature = sign("", timestamp);
        Request request = new Request.Builder()
                .url(baseUrl + "/minecraft/connector/" + serverId + "/" + endpoint)
                .get()
                .addHeader("X-Connector-Timestamp", String.valueOf(timestamp))
                .addHeader("X-Connector-Signature", signature)
                .build();
        return parse(request);
    }

    private JsonObject parse(Request request) throws IOException {
        try (Response response = http.newCall(request).execute()) {
            String text = response.body() != null ? response.body().string() : "{}";
            if (!response.isSuccessful()) {
                throw new IOException("HTTP " + response.code() + ": " + text);
            }
            return GSON.fromJson(text, JsonObject.class);
        }
    }

    private String sign(String payload, long timestamp) {
        return ConnectorSigner.sign(secret, payload, timestamp);
    }

    private interface IoSupplier {
        JsonObject get() throws IOException;
    }

    private JsonObject executeWithRetry(IoSupplier supplier) throws IOException {
        IOException last = null;
        for (int attempt = 0; attempt < 3; attempt++) {
            try {
                return supplier.get();
            } catch (IOException ex) {
                last = ex;
                try {
                    Thread.sleep(500L * (attempt + 1));
                } catch (InterruptedException ignored) {
                    Thread.currentThread().interrupt();
                }
            }
        }
        throw last;
    }
}
