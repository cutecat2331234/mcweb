package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;

import java.io.IOException;
import java.util.Collections;
import java.util.HashMap;
import java.util.HashSet;
import java.util.Map;
import java.util.Set;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.logging.Level;
import java.util.logging.Logger;

public final class TaskPoller {
    public interface TaskExecutor {
        void execute(JsonObject task, Completion completion);
    }

    public interface Completion {
        void succeed(String message);

        void fail(String error);

        /**
         * Completes a task with a structured result. Existing Completion
         * implementations remain source compatible through this default.
         */
        default void succeed(JsonObject result) {
            succeed(result == null ? null : result.toString());
        }

        /**
         * Fails a task with a structured result. Existing Completion
         * implementations remain source compatible through this default.
         */
        default void fail(JsonObject result) {
            fail(result == null ? null : result.toString());
        }
    }

    private final ConnectorTransport client;
    private final ProcessedDeliveryStore deliveryStore;
    private final TaskReceiptStore receiptStore;
    private final TaskExecutor executor;
    private final Logger logger;
    private final Set<String> inFlightDeliveries = Collections.synchronizedSet(new HashSet<String>());
    private final Set<String> inFlightTaskIds = Collections.synchronizedSet(new HashSet<String>());
    private final Map<String, JsonObject> pendingReceiptWrites = Collections.synchronizedMap(
            new HashMap<String, JsonObject>()
    );
    private final Object pollLock = new Object();

    public TaskPoller(ConnectorClient client, ProcessedDeliveryStore deliveryStore, TaskExecutor executor, Logger logger) {
        this(client, deliveryStore, new TaskReceiptStore(deliveryStore.dataFolder()), executor, logger);
    }

    TaskPoller(
            ConnectorTransport client,
            ProcessedDeliveryStore deliveryStore,
            TaskReceiptStore receiptStore,
            TaskExecutor executor,
            Logger logger
    ) {
        this.client = client;
        this.deliveryStore = deliveryStore;
        this.receiptStore = receiptStore;
        this.executor = executor;
        this.logger = logger;
    }

    public void poll() {
        synchronized (pollLock) {
            try {
                JsonObject response = client.get("tasks");
                if (response == null || !response.has("tasks") || !response.get("tasks").isJsonArray()) {
                    return;
                }

                JsonArray tasks = response.getAsJsonArray("tasks");
                for (int i = 0; i < tasks.size(); i++) {
                    try {
                        if (!tasks.get(i).isJsonObject()) {
                            logger.log(Level.WARNING, "ignored malformed polled task at index " + i);
                            continue;
                        }
                        handleTask(tasks.get(i).getAsJsonObject());
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

        if (deliveryId != null) {
            JsonObject storedResult = receiptStore.find(deliveryId);
            if (storedResult != null) {
                acknowledgeStoredResult(task, deliveryId, storedResult);
                return;
            }

            JsonObject pendingResult = pendingReceiptWrites.get(deliveryId);
            if (pendingResult != null) {
                persistAndAcknowledge(task, deliveryId, pendingResult);
                return;
            }

            // Compatibility for deliveries completed before structured receipt
            // storage existed. These retain the former acknowledgement body.
            if (deliveryStore.contains(deliveryId)) {
                completeTask(task, CompletionResultPolicy.legacySuccess("already processed locally"));
                return;
            }
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

        AtomicBoolean completed = new AtomicBoolean();
        Completion completion = new Completion() {
            @Override
            public void succeed(String message) {
                finish(CompletionResultPolicy.legacySuccess(message), true);
            }

            @Override
            public void fail(String error) {
                // Preserve the pre-structured API contract: legacy failures
                // are attempts that may execute again for the same delivery.
                finish(CompletionResultPolicy.legacyFailure(error), false);
            }

            @Override
            public void succeed(JsonObject result) {
                finish(CompletionResultPolicy.normalize(true, result), true);
            }

            @Override
            public void fail(JsonObject result) {
                JsonObject normalized = CompletionResultPolicy.normalize(false, result);
                // Structured failures are terminal unless the executor makes
                // retryability explicit. A retry should normally use a new
                // delivery/attempt identifier supplied by the control plane.
                finish(normalized, !isExplicitlyRetryable(normalized));
            }

            private void finish(JsonObject result, boolean persistTerminalResult) {
                if (!completed.compareAndSet(false, true)) {
                    logger.log(Level.WARNING, "ignored duplicate completion for task " + taskId);
                    return;
                }

                if (deliveryId != null && persistTerminalResult) {
                    pendingReceiptWrites.put(deliveryId, result.deepCopy());
                    clearInFlight(deliveryId, taskId);
                    persistAndAcknowledge(task, deliveryId, result);
                } else {
                    clearInFlight(deliveryId, taskId);
                    completeTask(task, result);
                }
            }
        };

        try {
            executor.execute(task, completion);
        } catch (Exception ex) {
            logger.log(Level.WARNING, "task executor failed before completion", ex);
            completion.fail(ex.getMessage() == null ? "task execution failed" : ex.getMessage());
        }
    }

    private void persistAndAcknowledge(JsonObject task, String deliveryId, JsonObject proposedResult) {
        JsonObject storedResult = receiptStore.putIfAbsent(deliveryId, proposedResult);
        if (storedResult == null) {
            pendingReceiptWrites.put(deliveryId, proposedResult.deepCopy());
            logger.log(Level.WARNING, "deferred acknowledgement because receipt could not be persisted for " + deliveryId);
            return;
        }

        pendingReceiptWrites.remove(deliveryId);
        deliveryStore.add(deliveryId);
        acknowledgeStoredResult(task, deliveryId, storedResult);
    }

    private void acknowledgeStoredResult(JsonObject task, String deliveryId, JsonObject storedResult) {
        if (completeTask(task, storedResult)) {
            pendingReceiptWrites.remove(deliveryId);
            deliveryStore.add(deliveryId);
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

    private boolean completeTask(JsonObject task, JsonObject result) {
        String taskId = taskId(task);
        if (taskId == null) {
            logger.log(Level.WARNING, "cannot complete task without id");
            return false;
        }

        try {
            JsonObject body = new JsonObject();
            body.add("result", result.deepCopy());
            client.post("tasks/" + taskId + "/complete", body);
            return true;
        } catch (IOException ex) {
            logger.log(Level.WARNING, "failed to complete task " + taskId, ex);
            return false;
        }
    }

    private static String deliveryId(JsonObject task) {
        String value = stringField(task, "delivery_id");
        return TaskReceiptStore.validDeliveryId(value) ? value : null;
    }

    private static String taskId(JsonObject task) {
        return stringField(task, "id");
    }

    private static boolean isExplicitlyRetryable(JsonObject result) {
        return result.has("retryable") && result.get("retryable").isJsonPrimitive()
                && result.getAsJsonPrimitive("retryable").isBoolean()
                && result.getAsJsonPrimitive("retryable").getAsBoolean();
    }

    private static String stringField(JsonObject object, String name) {
        if (!object.has(name) || object.get(name).isJsonNull() || !object.get(name).isJsonPrimitive()
                || !object.getAsJsonPrimitive(name).isString()) {
            return null;
        }
        try {
            String value = object.get(name).getAsString();
            return value == null || value.isEmpty() ? null : value;
        } catch (UnsupportedOperationException ex) {
            return null;
        }
    }
}
