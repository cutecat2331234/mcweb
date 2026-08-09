package com.mcweb.connector.common;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.io.File;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.ArrayList;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import java.util.logging.Level;
import java.util.logging.Logger;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

class TaskPollerTest {
    @TempDir
    Path temporaryDirectory;

    @Test
    void structuredSuccessIsCanonicalAndPersistsOnlyTheExecutorResult() throws Exception {
        JsonObject task = task("task-1", "delivery-1");
        task.addProperty("secret", "must-not-be-persisted");
        JsonObject requestPayload = new JsonObject();
        requestPayload.addProperty("command", "must-not-be-persisted-either");
        task.add("payload", requestPayload);

        FakeTransport transport = new FakeTransport(task);
        Stores stores = stores();
        TaskPoller poller = poller(transport, stores, (ignored, completion) -> {
            JsonObject result = new JsonObject();
            result.addProperty("success", false);
            result.addProperty("status", "executor-specific-status");
            result.addProperty("receipt_reference", "remote-42");
            completion.succeed(result);
        });

        poller.poll();

        JsonObject acknowledged = transport.lastResult();
        assertTrue(acknowledged.get("success").getAsBoolean());
        assertEquals("completed", acknowledged.get("status").getAsString());
        assertEquals("remote-42", acknowledged.get("receipt_reference").getAsString());
        assertEquals(acknowledged, stores.receipts.find("delivery-1"));

        File[] files = stores.receipts.receiptDirectory().listFiles(File::isFile);
        assertNotNull(files);
        assertEquals(1, files.length);
        String persisted = new String(Files.readAllBytes(files[0].toPath()), StandardCharsets.UTF_8);
        assertFalse(persisted.contains("must-not-be-persisted"));
        assertFalse(persisted.contains("must-not-be-persisted-either"));
        assertFalse(persisted.contains("payload"));
    }

    @Test
    void networkFailureRetriesTheExactStoredResultWithoutExecutingAgain() {
        JsonObject task = task("task-2", "delivery-2");
        FakeTransport transport = new FakeTransport(task);
        transport.failedPostsRemaining = 1;
        Stores stores = stores();
        AtomicInteger executions = new AtomicInteger();
        TaskPoller poller = poller(transport, stores, (ignored, completion) -> {
            executions.incrementAndGet();
            JsonObject result = new JsonObject();
            result.addProperty("external_reference", "same-on-every-ack");
            completion.succeed(result);
        });

        poller.poll();
        poller.poll();

        assertEquals(1, executions.get());
        assertEquals(2, transport.postBodies.size());
        assertEquals(transport.postBodies.get(0), transport.postBodies.get(1));
        assertEquals("same-on-every-ack", transport.lastResult().get("external_reference").getAsString());
    }

    @Test
    void processRestartReplaysTheExactReceiptWithoutExecutingAgain() {
        JsonObject task = task("task-3", "delivery-3");
        Stores firstStores = stores();
        FakeTransport firstTransport = new FakeTransport(task);
        firstTransport.failedPostsRemaining = 1;
        TaskPoller firstPoller = poller(firstTransport, firstStores, (ignored, completion) -> {
            JsonObject result = new JsonObject();
            result.addProperty("attempt_id", "immutable-attempt");
            completion.succeed(result);
        });
        firstPoller.poll();

        ProcessedDeliveryStore restartedProcessed = new ProcessedDeliveryStore(temporaryDirectory.toFile());
        TaskReceiptStore restartedReceipts = new TaskReceiptStore(temporaryDirectory.toFile());
        Stores restartedStores = new Stores(restartedProcessed, restartedReceipts);
        FakeTransport restartedTransport = new FakeTransport(task);
        AtomicInteger restartedExecutions = new AtomicInteger();
        TaskPoller restartedPoller = poller(restartedTransport, restartedStores, (ignored, completion) ->
                restartedExecutions.incrementAndGet()
        );

        restartedPoller.poll();

        assertEquals(0, restartedExecutions.get());
        assertEquals(firstTransport.postBodies.get(0), restartedTransport.postBodies.get(0));
        assertEquals("immutable-attempt", restartedTransport.lastResult().get("attempt_id").getAsString());
    }

    @Test
    void duplicateDeliveryAfterAcknowledgementDoesNotExecuteTwice() {
        JsonObject task = task("task-4", "delivery-4");
        FakeTransport transport = new FakeTransport(task);
        Stores stores = stores();
        AtomicInteger executions = new AtomicInteger();
        TaskPoller poller = poller(transport, stores, (ignored, completion) -> {
            executions.incrementAndGet();
            completion.succeed("done once");
        });

        poller.poll();
        poller.poll();

        assertEquals(1, executions.get());
        assertEquals(2, transport.postBodies.size());
        assertEquals(transport.postBodies.get(0), transport.postBodies.get(1));
    }

    @Test
    void structuredFailureIsCanonicalAndTerminalByDefault() {
        JsonObject task = task("task-5", "delivery-5");
        FakeTransport transport = new FakeTransport(task);
        Stores stores = stores();
        AtomicInteger executions = new AtomicInteger();
        TaskPoller poller = poller(transport, stores, (ignored, completion) -> {
            executions.incrementAndGet();
            JsonObject result = new JsonObject();
            result.addProperty("success", true);
            result.addProperty("status", "completed");
            result.addProperty("error_code", "executor_rejected");
            result.addProperty("detail", "generic rejection");
            completion.fail(result);
        });

        poller.poll();
        poller.poll();

        JsonObject acknowledged = transport.lastResult();
        assertFalse(acknowledged.get("success").getAsBoolean());
        assertEquals("failed", acknowledged.get("status").getAsString());
        assertEquals("executor_rejected", acknowledged.get("error_code").getAsString());
        assertEquals("task execution failed", acknowledged.get("error").getAsString());
        assertEquals(1, executions.get());
        assertEquals(transport.postBodies.get(0), transport.postBodies.get(1));
        assertEquals(acknowledged, stores.receipts.find("delivery-5"));
        assertTrue(stores.processed.contains("delivery-5"));
    }

    @Test
    void structuredFailureSurvivesLostAcknowledgementAndProcessRestart() {
        JsonObject task = task("task-5-restart", "delivery-5-restart");
        Stores firstStores = stores();
        FakeTransport firstTransport = new FakeTransport(task);
        firstTransport.failedPostsRemaining = 1;
        AtomicInteger executions = new AtomicInteger();
        TaskPoller firstPoller = poller(firstTransport, firstStores, (ignored, completion) -> {
            executions.incrementAndGet();
            JsonObject failure = new JsonObject();
            failure.addProperty("error_code", "stable_failure");
            failure.addProperty("attempt_reference", "attempt-one");
            completion.fail(failure);
        });
        firstPoller.poll();

        FakeTransport restartedTransport = new FakeTransport(task);
        Stores restartedStores = new Stores(
                new ProcessedDeliveryStore(temporaryDirectory.toFile()),
                new TaskReceiptStore(temporaryDirectory.toFile())
        );
        TaskPoller restartedPoller = poller(restartedTransport, restartedStores, (ignored, completion) ->
                executions.incrementAndGet()
        );
        restartedPoller.poll();

        assertEquals(1, executions.get());
        assertEquals(firstTransport.postBodies.get(0), restartedTransport.postBodies.get(0));
        assertEquals("stable_failure", restartedTransport.lastResult().get("error_code").getAsString());
        assertEquals("attempt-one", restartedTransport.lastResult().get("attempt_reference").getAsString());
    }

    @Test
    void legacyStringFailureStillExecutesAgainForTheSameDelivery() {
        JsonObject task = task("task-5-legacy", "delivery-5-legacy");
        FakeTransport transport = new FakeTransport(task);
        Stores stores = stores();
        AtomicInteger executions = new AtomicInteger();
        TaskPoller poller = poller(transport, stores, (ignored, completion) -> {
            executions.incrementAndGet();
            completion.fail("legacy retryable failure");
        });

        poller.poll();
        poller.poll();

        assertEquals(2, executions.get());
        assertNull(stores.receipts.find("delivery-5-legacy"));
        assertFalse(stores.processed.contains("delivery-5-legacy"));
        assertEquals("legacy retryable failure", transport.lastResult().get("error").getAsString());
    }

    @Test
    void structuredFailureCanExplicitlyRemainRetryable() {
        JsonObject task = task("task-5-retryable", "delivery-5-retryable");
        FakeTransport transport = new FakeTransport(task);
        Stores stores = stores();
        AtomicInteger executions = new AtomicInteger();
        TaskPoller poller = poller(transport, stores, (ignored, completion) -> {
            executions.incrementAndGet();
            JsonObject failure = new JsonObject();
            failure.addProperty("error_code", "temporary_failure");
            failure.addProperty("retryable", true);
            completion.fail(failure);
        });

        poller.poll();
        poller.poll();

        assertEquals(2, executions.get());
        assertNull(stores.receipts.find("delivery-5-retryable"));
        assertFalse(stores.processed.contains("delivery-5-retryable"));
        assertTrue(transport.lastResult().get("retryable").getAsBoolean());
    }

    @Test
    void legacyStringCompletionKeepsItsAcknowledgementShape() {
        JsonObject task = task("task-6", "delivery-6");
        FakeTransport transport = new FakeTransport(task);
        Stores stores = stores();
        TaskPoller poller = poller(transport, stores, (ignored, completion) -> completion.succeed("legacy message"));

        poller.poll();

        JsonObject result = transport.lastResult();
        assertTrue(result.get("success").getAsBoolean());
        assertEquals("completed", result.get("status").getAsString());
        assertEquals("legacy message", result.get("message").getAsString());
        assertEquals(3, result.size());
    }

    @Test
    void corruptReceiptIsQuarantinedAndLegacyMarkerStillPreventsExecution() throws Exception {
        JsonObject task = task("task-7", "delivery-7");
        Stores stores = stores();
        stores.receipts.putIfAbsent("delivery-7", CompletionResultPolicy.legacySuccess("original"));
        stores.processed.add("delivery-7");

        File[] receiptFiles = stores.receipts.receiptDirectory().listFiles(File::isFile);
        assertNotNull(receiptFiles);
        assertEquals(1, receiptFiles.length);
        Files.write(receiptFiles[0].toPath(), "not-json".getBytes(StandardCharsets.UTF_8));

        TaskReceiptStore restartedReceipts = new TaskReceiptStore(temporaryDirectory.toFile());
        assertNull(restartedReceipts.find("delivery-7"));
        File[] quarantined = restartedReceipts.quarantineDirectory().listFiles(File::isFile);
        assertNotNull(quarantined);
        assertEquals(1, quarantined.length);

        FakeTransport transport = new FakeTransport(task);
        AtomicInteger executions = new AtomicInteger();
        TaskPoller poller = poller(
                transport,
                new Stores(new ProcessedDeliveryStore(temporaryDirectory.toFile()), restartedReceipts),
                (ignored, completion) -> executions.incrementAndGet()
        );
        poller.poll();

        assertEquals(0, executions.get());
        assertEquals("already processed locally", transport.lastResult().get("message").getAsString());
    }

    @Test
    void oversizedOrSensitiveStructuredResultsAreRejectedWithABoundedFailure() {
        JsonObject task = task("task-8", "delivery-8");
        FakeTransport transport = new FakeTransport(task);
        Stores stores = stores();
        TaskPoller poller = poller(transport, stores, (ignored, completion) -> {
            JsonObject result = new JsonObject();
            result.addProperty("secret", repeat('x', 9_000));
            completion.succeed(result);
        });

        poller.poll();

        JsonObject result = transport.lastResult();
        assertFalse(result.get("success").getAsBoolean());
        assertEquals("failed", result.get("status").getAsString());
        assertEquals("invalid_result_payload", result.get("error_code").getAsString());
        assertFalse(result.toString().contains(repeat('x', 100)));
        assertEquals(result, stores.receipts.find("delivery-8"));
        assertTrue(stores.processed.contains("delivery-8"));
    }

    @Test
    void receiptRetentionIsBounded() {
        Logger logger = quietLogger();
        TaskReceiptStore receipts = new TaskReceiptStore(temporaryDirectory.toFile(), 2, 2, logger);
        for (int i = 0; i < 3; i++) {
            assertNotNull(receipts.putIfAbsent("bounded-" + i, CompletionResultPolicy.legacySuccess("ok-" + i)));
        }

        File[] files = receipts.receiptDirectory().listFiles(File::isFile);
        assertNotNull(files);
        assertEquals(2, files.length);
        assertNotNull(receipts.find("bounded-2"));
    }

    @Test
    void corruptReceiptQuarantineIsBounded() throws Exception {
        TaskReceiptStore receipts = new TaskReceiptStore(temporaryDirectory.toFile(), 4, 2, quietLogger());
        for (int i = 0; i < 3; i++) {
            String deliveryId = "corrupt-bounded-" + i;
            assertNotNull(receipts.putIfAbsent(deliveryId, CompletionResultPolicy.legacySuccess("ok")));
            Files.write(receipts.receiptFile(deliveryId).toPath(), "broken".getBytes(StandardCharsets.UTF_8));
            assertNull(receipts.find(deliveryId));
        }

        File[] quarantined = receipts.quarantineDirectory().listFiles(File::isFile);
        assertNotNull(quarantined);
        assertEquals(2, quarantined.length);
    }

    private Stores stores() {
        return new Stores(
                new ProcessedDeliveryStore(temporaryDirectory.toFile()),
                new TaskReceiptStore(temporaryDirectory.toFile())
        );
    }

    private TaskPoller poller(FakeTransport transport, Stores stores, TaskPoller.TaskExecutor executor) {
        return new TaskPoller(transport, stores.processed, stores.receipts, executor, quietLogger());
    }

    private static JsonObject task(String taskId, String deliveryId) {
        JsonObject task = new JsonObject();
        task.addProperty("id", taskId);
        task.addProperty("delivery_id", deliveryId);
        return task;
    }

    private static Logger quietLogger() {
        Logger logger = Logger.getLogger(TaskPollerTest.class.getName() + "." + System.nanoTime());
        logger.setLevel(Level.OFF);
        logger.setUseParentHandlers(false);
        return logger;
    }

    private static String repeat(char character, int count) {
        StringBuilder value = new StringBuilder(count);
        for (int i = 0; i < count; i++) {
            value.append(character);
        }
        return value.toString();
    }

    private static final class Stores {
        private final ProcessedDeliveryStore processed;
        private final TaskReceiptStore receipts;

        private Stores(ProcessedDeliveryStore processed, TaskReceiptStore receipts) {
            this.processed = processed;
            this.receipts = receipts;
        }
    }

    private static final class FakeTransport implements ConnectorTransport {
        private final JsonObject response;
        private final List<JsonObject> postBodies = new ArrayList<JsonObject>();
        private int failedPostsRemaining;

        private FakeTransport(JsonObject task) {
            JsonArray tasks = new JsonArray();
            tasks.add(task.deepCopy());
            response = new JsonObject();
            response.add("tasks", tasks);
        }

        @Override
        public JsonObject post(String endpoint, JsonObject body) throws IOException {
            postBodies.add(body.deepCopy());
            if (failedPostsRemaining > 0) {
                failedPostsRemaining--;
                throw new IOException("simulated acknowledgement failure");
            }
            return new JsonObject();
        }

        @Override
        public JsonObject get(String endpoint) {
            return response.deepCopy();
        }

        private JsonObject lastResult() {
            return postBodies.get(postBodies.size() - 1).getAsJsonObject("result");
        }
    }
}
