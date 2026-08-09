package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonPrimitive;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.HashSet;
import java.util.Locale;
import java.util.Map;
import java.util.Set;

final class CompletionResultPolicy {
    static final int MAX_SERIALIZED_BYTES = 32 * 1024;

    private static final int MAX_DEPTH = 8;
    private static final int MAX_NODES = 512;
    private static final int MAX_CONTAINER_ENTRIES = 256;
    private static final int MAX_KEY_CHARACTERS = 128;
    private static final int MAX_STRING_CHARACTERS = 8 * 1024;
    private static final Set<String> SENSITIVE_OR_REQUEST_KEYS = new HashSet<String>(Arrays.asList(
            "authorization",
            "client_secret",
            "cookie",
            "password",
            "raw_request",
            "request",
            "request_body",
            "secret",
            "set_cookie",
            "task",
            "task_body"
    ));

    private CompletionResultPolicy() {
    }

    static JsonObject legacySuccess(String message) {
        JsonObject result = new JsonObject();
        result.addProperty("message", boundedLegacyText(message));
        return normalize(true, result);
    }

    static JsonObject legacyFailure(String error) {
        String boundedError = boundedLegacyText(error);
        if (boundedError == null || boundedError.isEmpty()) {
            boundedError = "task execution failed";
        }

        JsonObject result = new JsonObject();
        result.addProperty("message", boundedError);
        result.addProperty("error", boundedError);
        return normalize(false, result);
    }

    static JsonObject normalize(boolean requestedSuccess, JsonObject supplied) {
        if (supplied == null || !hasSafeShape(supplied)) {
            return invalidPayloadResult();
        }

        JsonObject result = supplied.deepCopy();
        result.addProperty("success", requestedSuccess);
        result.addProperty("status", requestedSuccess ? "completed" : "failed");

        if (!requestedSuccess && !hasUsableError(result)) {
            result.addProperty("error", fallbackError(result));
        }

        if (!hasSafeShape(result) || serializedSize(result) > MAX_SERIALIZED_BYTES) {
            return invalidPayloadResult();
        }
        return result;
    }

    static boolean isCanonical(JsonObject result) {
        if (result == null || !hasSafeShape(result) || serializedSize(result) > MAX_SERIALIZED_BYTES) {
            return false;
        }
        if (!result.has("success") || !result.get("success").isJsonPrimitive()) {
            return false;
        }

        JsonPrimitive successValue = result.getAsJsonPrimitive("success");
        if (!successValue.isBoolean() || !result.has("status") || !result.get("status").isJsonPrimitive()) {
            return false;
        }

        JsonPrimitive statusValue = result.getAsJsonPrimitive("status");
        if (!statusValue.isString()) {
            return false;
        }

        boolean success = successValue.getAsBoolean();
        String status = statusValue.getAsString();
        return success ? "completed".equals(status) : "failed".equals(status);
    }

    private static JsonObject invalidPayloadResult() {
        JsonObject result = new JsonObject();
        result.addProperty("success", false);
        result.addProperty("status", "failed");
        result.addProperty("error", "invalid completion result payload");
        result.addProperty("error_code", "invalid_result_payload");
        return result;
    }

    private static boolean hasSafeShape(JsonElement root) {
        ShapeBudget budget = new ShapeBudget();
        return inspect(root, 0, budget);
    }

    private static boolean inspect(JsonElement element, int depth, ShapeBudget budget) {
        if (element == null || depth > MAX_DEPTH || ++budget.nodes > MAX_NODES) {
            return false;
        }
        if (element.isJsonNull()) {
            return true;
        }
        if (element.isJsonPrimitive()) {
            JsonPrimitive primitive = element.getAsJsonPrimitive();
            if (primitive.isString()) {
                return primitive.getAsString().length() <= MAX_STRING_CHARACTERS;
            }
            if (primitive.isNumber()) {
                double number = primitive.getAsDouble();
                return !Double.isNaN(number) && !Double.isInfinite(number);
            }
            return primitive.isBoolean();
        }
        if (element.isJsonArray()) {
            JsonArray array = element.getAsJsonArray();
            if (array.size() > MAX_CONTAINER_ENTRIES) {
                return false;
            }
            for (JsonElement child : array) {
                if (!inspect(child, depth + 1, budget)) {
                    return false;
                }
            }
            return true;
        }
        if (!element.isJsonObject()) {
            return false;
        }

        JsonObject object = element.getAsJsonObject();
        if (object.size() > MAX_CONTAINER_ENTRIES) {
            return false;
        }
        for (Map.Entry<String, JsonElement> entry : object.entrySet()) {
            String key = entry.getKey();
            if (key == null || key.length() > MAX_KEY_CHARACTERS || isSensitiveOrRequestKey(key)) {
                return false;
            }
            if (!inspect(entry.getValue(), depth + 1, budget)) {
                return false;
            }
        }
        return true;
    }

    private static boolean isSensitiveOrRequestKey(String key) {
        String normalized = key.toLowerCase(Locale.ROOT).replace('-', '_');
        return SENSITIVE_OR_REQUEST_KEYS.contains(normalized)
                || normalized.contains("secret")
                || normalized.contains("password")
                || normalized.contains("token")
                || normalized.contains("credential");
    }

    private static boolean hasUsableError(JsonObject result) {
        if (!result.has("error") || !result.get("error").isJsonPrimitive()) {
            return false;
        }
        JsonPrimitive error = result.getAsJsonPrimitive("error");
        return error.isString() && !error.getAsString().isEmpty();
    }

    private static String fallbackError(JsonObject result) {
        if (result.has("message") && result.get("message").isJsonPrimitive()) {
            JsonPrimitive message = result.getAsJsonPrimitive("message");
            if (message.isString() && !message.getAsString().isEmpty()) {
                return message.getAsString();
            }
        }
        return "task execution failed";
    }

    private static int serializedSize(JsonObject result) {
        return result.toString().getBytes(StandardCharsets.UTF_8).length;
    }

    private static String boundedLegacyText(String value) {
        if (value == null || value.length() <= MAX_STRING_CHARACTERS) {
            return value;
        }
        return value.substring(0, MAX_STRING_CHARACTERS);
    }

    private static final class ShapeBudget {
        private int nodes;
    }
}
