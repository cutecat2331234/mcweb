package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.io.IOException;
import java.util.Collections;
import java.util.HashSet;
import java.util.Set;
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
    private final Set<String> inFlightDeliveries = Collections.synchronizedSet(new HashSet<String>());
    private final Set<String> pendingAckDeliveries = Collections.synchronizedSet(new HashSet<String>());
    private final Set<String> inFlightTaskIds = Collections.synchronizedSet(new HashSet<String>());
    private final Object pollLock = new Object();

    public TaskPoller(ConnectorClient client, ProcessedDeliveryStore deliveryStore, TaskExecutor executor, Logger logger) {
        this.client = client;
        this.deliveryStore = deliveryStore;
        this.executor = executor;
        this.logger = logger;
    }

    public void poll() {
        synchronized (pollLock) {
            try {
                JsonObject response = client.get("tasks");
                if (!response.has("tasks")) {
                    return;
                }

                JsonArray tasks = response.getAsJsonArray("tasks");
                for (int i = 0; i < tasks.size(); i++) {
                    try {
                        JsonObject task = tasks.get(i).getAsJsonObject();
                        handleTask(task);
                    } catch (Exception ex) {
                        logger.log(Level.WARNING, "failed to handle polled task", ex);
                    }
                }
            } catch (IOException ex) {
                logger.log(Level.FINE, "task poll failed", ex);
            }
        }
    }

    private void handleTask(JsonObject task) {
        String deliveryId = deliveryId(task);
        String taskId = taskId(task);

        if (deliveryId != null && deliveryStore.contains(deliveryId)) {
            completeTask(task, true, "already processed locally");
            return;
        }

        if (deliveryId != null && pendingAckDeliveries.contains(deliveryId)) {
            acknowledgeSuccessfulExecution(task, deliveryId, "retry complete");
            return;
        }

        if (deliveryId != null && inFlightDeliveries.contains(deliveryId)) {
            return;
        }

        if (deliveryId == null && taskId != null && inFlightTaskIds.contains(taskId)) {
            return;
        }

        if (deliveryId != null) {
            inFlightDeliveries.add(deliveryId);
        } else if (taskId != null) {
            inFlightTaskIds.add(taskId);
        }

        Completion completion = new Completion() {
            @Override
            public void succeed(String message) {
                if (deliveryId != null) {
                    pendingAckDeliveries.add(deliveryId);
                }
                clearInFlight(deliveryId, taskId);
                if (deliveryId != null) {
                    acknowledgeSuccessfulExecution(task, deliveryId, message);
                } else {
                    completeTask(task, true, message);
                }
            }

            @Override
            public void fail(String error) {
                clearInFlight(deliveryId, taskId);
                completeTask(task, false, error);
            }
        };

        try {
            executor.execute(task, completion);
        } catch (Exception ex) {
            logger.log(Level.WARNING, "task executor failed before completion", ex);
            completion.fail(ex.getMessage() == null ? "task execution failed" : ex.getMessage());
        }
    }

    private void acknowledgeSuccessfulExecution(JsonObject task, String deliveryId, String message) {
        if (completeTask(task, true, message)) {
            pendingAckDeliveries.remove(deliveryId);
            deliveryStore.add(deliveryId);
        } else {
            pendingAckDeliveries.add(deliveryId);
        }
    }

    private void clearInFlight(String deliveryId, String taskId) {
        if (deliveryId != null) {
            inFlightDeliveries.remove(deliveryId);
        }
        if (taskId != null) {
            inFlightTaskIds.remove(taskId);
        }
    }

    private boolean completeTask(JsonObject task, boolean success, String message) {
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

            String taskId = taskId(task);
            if (taskId == null) {
                logger.log(Level.WARNING, "cannot complete task without id");
                return false;
            }

            client.post("tasks/" + taskId + "/complete", body);
            return true;
        } catch (IOException ex) {
            logger.log(Level.WARNING, "failed to complete task " + taskId(task), ex);
            return false;
        }
    }

    private static String deliveryId(JsonObject task) {
        return task.has("delivery_id") && !task.get("delivery_id").isJsonNull()
                ? task.get("delivery_id").getAsString()
                : null;
    }

    private static String taskId(JsonObject task) {
        return task.has("id") && !task.get("id").isJsonNull()
                ? task.get("id").getAsString()
                : null;
    }
}
