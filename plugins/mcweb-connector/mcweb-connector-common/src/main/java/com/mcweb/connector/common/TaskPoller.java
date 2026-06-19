package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.io.IOException;
import java.util.logging.Level;
import java.util.logging.Logger;

public final class TaskPoller {
    public interface TaskExecutor {
        void execute(JsonObject task, Completion completion);
    }

    public interface Completion {
        void succeed(String message);

        void fail(String error);
    }

    private final ConnectorClient client;
    private final ProcessedDeliveryStore deliveryStore;
    private final TaskExecutor executor;
    private final Logger logger;

    public TaskPoller(ConnectorClient client, ProcessedDeliveryStore deliveryStore, TaskExecutor executor, Logger logger) {
        this.client = client;
        this.deliveryStore = deliveryStore;
        this.executor = executor;
        this.logger = logger;
    }

    public void poll() {
        try {
            JsonObject response = client.get("tasks");
            if (!response.has("tasks")) {
                return;
            }
            JsonArray tasks = response.getAsJsonArray("tasks");
            for (int i = 0; i < tasks.size(); i++) {
                JsonObject task = tasks.get(i).getAsJsonObject();
                handleTask(task);
            }
        } catch (IOException ex) {
            logger.log(Level.FINE, "task poll failed", ex);
        }
    }

    private void handleTask(JsonObject task) {
        String deliveryId = task.has("delivery_id") && !task.get("delivery_id").isJsonNull()
                ? task.get("delivery_id").getAsString()
                : null;

        if (deliveryId != null && deliveryStore.contains(deliveryId)) {
            completeTask(task, true, "already processed locally");
            return;
        }

        executor.execute(task, new Completion() {
            @Override
            public void succeed(String message) {
                completeTask(task, true, message);
            }

            @Override
            public void fail(String error) {
                completeTask(task, false, error);
            }
        });
    }

    private void completeTask(JsonObject task, boolean success, String message) {
        try {
            JsonObject body = new JsonObject();
            JsonObject result = new JsonObject();
            result.addProperty("success", success);
            result.addProperty("status", success ? "completed" : "failed");
            result.addProperty("message", message);
            if (!success) {
                result.addProperty("error", message);
            }
            body.add("result", result);

            String taskId = task.get("id").getAsString();
            client.post("tasks/" + taskId + "/complete", body);

            if (success && task.has("delivery_id") && !task.get("delivery_id").isJsonNull()) {
                deliveryStore.add(task.get("delivery_id").getAsString());
            }
        } catch (IOException ex) {
            logger.log(Level.WARNING, "failed to complete task " + task.get("id"), ex);
        }
    }
}
