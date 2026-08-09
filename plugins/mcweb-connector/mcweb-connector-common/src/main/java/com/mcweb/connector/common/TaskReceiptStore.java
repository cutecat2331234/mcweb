package com.mcweb.connector.common;

import com.google.gson.Gson;
import com.google.gson.JsonElement;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.io.ByteArrayInputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.AtomicMoveNotSupportedException;
import java.nio.file.Files;
import java.nio.file.StandardCopyOption;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.util.Arrays;
import java.util.Comparator;
import java.util.concurrent.atomic.AtomicLong;
import java.util.logging.Level;
import java.util.logging.Logger;

/**
 * Stores the first terminal executor result for a delivery.
 *
 * Files contain only the delivery identifier and the bounded completion result;
 * the polled task, connector secret, and request body are never persisted here.
 */
public final class TaskReceiptStore {
    private static final Gson GSON = new Gson();
    private static final int SCHEMA_VERSION = 1;
    private static final int DEFAULT_MAX_RECEIPTS = 4_096;
    private static final int DEFAULT_MAX_QUARANTINED_FILES = 32;
    private static final int MAX_DELIVERY_ID_CHARACTERS = 512;
    private static final int MAX_ENVELOPE_BYTES = CompletionResultPolicy.MAX_SERIALIZED_BYTES + 2_048;
    private static final AtomicLong QUARANTINE_SEQUENCE = new AtomicLong();

    private final File receiptDirectory;
    private final File quarantineDirectory;
    private final int maxReceipts;
    private final int maxQuarantinedFiles;
    private final Logger logger;

    public TaskReceiptStore(File dataFolder) {
        this(dataFolder, DEFAULT_MAX_RECEIPTS, DEFAULT_MAX_QUARANTINED_FILES,
                Logger.getLogger(TaskReceiptStore.class.getName()));
    }

    TaskReceiptStore(File dataFolder, int maxReceipts, int maxQuarantinedFiles, Logger logger) {
        if (dataFolder == null) {
            throw new IllegalArgumentException("dataFolder is required");
        }
        if (maxReceipts < 1 || maxQuarantinedFiles < 1) {
            throw new IllegalArgumentException("retention limits must be positive");
        }
        this.receiptDirectory = new File(dataFolder, "task_receipts");
        this.quarantineDirectory = new File(receiptDirectory, "quarantine");
        this.maxReceipts = maxReceipts;
        this.maxQuarantinedFiles = maxQuarantinedFiles;
        this.logger = logger;
    }

    public synchronized JsonObject find(String deliveryId) {
        if (!validDeliveryId(deliveryId)) {
            return null;
        }
        File file = receiptFile(deliveryId);
        if (!file.isFile()) {
            return null;
        }

        try {
            JsonObject envelope = readEnvelope(file);
            if (!validEnvelope(envelope, deliveryId)) {
                quarantine(file, "invalid");
                return null;
            }
            return envelope.getAsJsonObject("result").deepCopy();
        } catch (Exception ex) {
            logger.log(Level.WARNING, "Failed to read connector task receipt " + file.getName(), ex);
            quarantine(file, "corrupt");
            return null;
        }
    }

    /**
     * Persists a terminal result if this is the first completion for the
     * delivery, returning the immutable result that owns the delivery.
     */
    public synchronized JsonObject putIfAbsent(String deliveryId, JsonObject result) {
        if (!validDeliveryId(deliveryId) || !CompletionResultPolicy.isCanonical(result)) {
            return null;
        }

        File target = receiptFile(deliveryId);
        JsonObject existing = find(deliveryId);
        if (existing != null) {
            return existing;
        }
        // A failed quarantine leaves the suspect target in place. Never
        // overwrite it and silently lose the evidence; defer acknowledgement
        // until storage can be repaired or the next poll can isolate it.
        if (target.exists()) {
            return null;
        }

        JsonObject envelope = new JsonObject();
        envelope.addProperty("schema_version", SCHEMA_VERSION);
        envelope.addProperty("delivery_id", deliveryId);
        envelope.add("result", result.deepCopy());

        byte[] bytes = GSON.toJson(envelope).getBytes(StandardCharsets.UTF_8);
        if (bytes.length > MAX_ENVELOPE_BYTES) {
            return null;
        }

        try {
            ensureDirectory(receiptDirectory);
            writeAtomically(target, bytes);
            trimReceipts(target);
            return result.deepCopy();
        } catch (IOException ex) {
            logger.log(Level.WARNING, "Failed to persist connector task receipt " + target.getName(), ex);
            return null;
        }
    }

    private JsonObject readEnvelope(File file) throws IOException {
        if (file.length() < 1 || file.length() > MAX_ENVELOPE_BYTES) {
            throw new IOException("receipt size is outside the accepted range");
        }

        byte[] bytes;
        try (InputStream input = new FileInputStream(file)) {
            bytes = readBounded(input, MAX_ENVELOPE_BYTES);
        }

        JsonElement parsed = JsonParser.parseReader(
                new java.io.InputStreamReader(new ByteArrayInputStream(bytes), StandardCharsets.UTF_8)
        );
        if (!parsed.isJsonObject()) {
            throw new IOException("receipt is not a JSON object");
        }
        return parsed.getAsJsonObject();
    }

    private boolean validEnvelope(JsonObject envelope, String deliveryId) {
        if (envelope.size() != 3
                || !envelope.has("schema_version") || !envelope.get("schema_version").isJsonPrimitive()
                || !envelope.getAsJsonPrimitive("schema_version").isNumber()
                || envelope.get("schema_version").getAsInt() != SCHEMA_VERSION) {
            return false;
        }
        if (!envelope.has("delivery_id") || !envelope.get("delivery_id").isJsonPrimitive()
                || !envelope.getAsJsonPrimitive("delivery_id").isString()
                || !deliveryId.equals(envelope.get("delivery_id").getAsString())) {
            return false;
        }
        return envelope.has("result") && envelope.get("result").isJsonObject()
                && CompletionResultPolicy.isCanonical(envelope.getAsJsonObject("result"));
    }

    private void writeAtomically(File target, byte[] bytes) throws IOException {
        File temporary = File.createTempFile("receipt-", ".tmp", receiptDirectory);
        boolean moved = false;
        try {
            try (FileOutputStream output = new FileOutputStream(temporary)) {
                output.write(bytes);
                output.flush();
                output.getFD().sync();
            }
            try {
                Files.move(temporary.toPath(), target.toPath(),
                        StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING);
            } catch (AtomicMoveNotSupportedException ex) {
                Files.move(temporary.toPath(), target.toPath(), StandardCopyOption.REPLACE_EXISTING);
            }
            moved = true;
        } finally {
            if (!moved && temporary.exists() && !temporary.delete()) {
                logger.log(Level.FINE, "Failed to remove temporary receipt " + temporary.getName());
            }
        }
    }

    private void quarantine(File file, String reason) {
        try {
            ensureDirectory(quarantineDirectory);
            String name = file.getName() + "." + reason + "." + System.currentTimeMillis()
                    + "." + QUARANTINE_SEQUENCE.incrementAndGet();
            Files.move(file.toPath(), new File(quarantineDirectory, name).toPath(),
                    StandardCopyOption.REPLACE_EXISTING);
            trimDirectory(quarantineDirectory, maxQuarantinedFiles);
        } catch (IOException ex) {
            logger.log(Level.WARNING, "Failed to quarantine connector task receipt " + file.getName(), ex);
        }
    }

    private void trimReceipts(File protectedReceipt) {
        trimDirectory(receiptDirectory, maxReceipts, protectedReceipt);
    }

    private void trimDirectory(File directory, int maximum) {
        trimDirectory(directory, maximum, null);
    }

    private void trimDirectory(File directory, int maximum, File protectedFile) {
        File[] files = directory.listFiles(file -> file.isFile() && !file.getName().endsWith(".tmp"));
        if (files == null || files.length <= maximum) {
            return;
        }
        Arrays.sort(files, Comparator.comparingLong(File::lastModified).thenComparing(File::getName));
        int remainingToDelete = files.length - maximum;
        for (File file : files) {
            if (remainingToDelete == 0) {
                break;
            }
            if (protectedFile != null && protectedFile.equals(file)) {
                continue;
            }
            if (file.delete()) {
                remainingToDelete--;
            } else {
                logger.log(Level.FINE, "Failed to trim connector receipt file " + file.getName());
            }
        }
    }

    File receiptFile(String deliveryId) {
        return new File(receiptDirectory, sha256(deliveryId) + ".json");
    }

    File receiptDirectory() {
        return receiptDirectory;
    }

    File quarantineDirectory() {
        return quarantineDirectory;
    }

    static boolean validDeliveryId(String deliveryId) {
        return deliveryId != null && !deliveryId.isEmpty()
                && deliveryId.length() <= MAX_DELIVERY_ID_CHARACTERS;
    }

    private static byte[] readBounded(InputStream input, int maximum) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[4_096];
        int read;
        while ((read = input.read(buffer)) != -1) {
            if (output.size() + read > maximum) {
                throw new IOException("receipt exceeds the accepted size");
            }
            output.write(buffer, 0, read);
        }
        return output.toByteArray();
    }

    private static void ensureDirectory(File directory) throws IOException {
        if (!directory.isDirectory() && !directory.mkdirs() && !directory.isDirectory()) {
            throw new IOException("could not create receipt directory " + directory);
        }
    }

    private static String sha256(String value) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] bytes = digest.digest(value.getBytes(StandardCharsets.UTF_8));
            StringBuilder hex = new StringBuilder(bytes.length * 2);
            for (byte item : bytes) {
                hex.append(String.format("%02x", item & 0xff));
            }
            return hex.toString();
        } catch (NoSuchAlgorithmException ex) {
            throw new IllegalStateException("SHA-256 is unavailable", ex);
        }
    }
}
